// pifinder-differ — on-demand + self-warming binary delta server for the
// PiFinder NixOS update transport.
//
// Serves zstd --patch-from patches between store-path export streams.
// Patches are computed over `nix-store --export` output so the device can
// verify (sha256) and `nix-store --import` the result. Pairs arrive two ways:
//   POST /delta  — a device names a target and the bases it holds (demand)
//   POST /warm   — enqueue every stem-paired path between two toplevels (warm)
// Demand jobs always run before warm jobs. All compute runs at the unit's
// idle CPU/IO priority so co-hosted services are never starved.

use std::collections::{HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, bail, Context, Result};
use axum::extract::{Path as AxPath, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::io::AsyncReadExt;
use tokio::process::Command;

const ALGO: &str = "zstd-patch-from-v1";
const WINDOW_LOG: u32 = 27; // 128 MiB — must match the device decoder
const RANK_LEVEL: u32 = 3; // cheap pass used only to pick the best base
const FINAL_LEVEL_SMALL: u32 = 19; // targets below the split
const FINAL_LEVEL_LARGE: u32 = 12; // large targets: 19 costs minutes for ~% gain
const LARGE_TARGET_BYTES: u64 = 20 * 1024 * 1024;
const KEEP_RATIO: f64 = 0.40; // patch bigger than 40% of the export: not worth it
const MIN_FREE_BYTES: u64 = 5 * 1024 * 1024 * 1024;
const DEMAND_QUEUE_CAP: usize = 64;
const WARM_QUEUE_CAP: usize = 10_000;

// ---------------------------------------------------------------- state

struct App {
    blob_dir: PathBuf,
    meta_dir: PathBuf,
    tmp_dir: PathBuf,
    substituters: Vec<String>,
    demand: Mutex<VecDeque<Job>>,
    warm: Mutex<VecDeque<Job>>,
    inflight: Mutex<HashSet<String>>, // target hashes being computed
    warm_runs: Mutex<Vec<WarmRun>>,
    jobs_done: AtomicU64,
    jobs_failed: AtomicU64,
}

#[derive(Clone)]
struct Job {
    target: String,       // full /nix/store/... path
    bases: Vec<String>,   // candidate bases, full paths, best guess first
    source: &'static str, // "demand" | "warm"
}

#[derive(Clone, Serialize)]
struct WarmRun {
    id: u64,
    base_toplevel: String,
    target_toplevel: String,
    state: String, // copying | pairing | queued | failed
    paired: usize,
    skipped_existing: usize,
    unpaired: usize,
    error: Option<String>,
    started_unix: u64,
}

#[derive(Serialize, Deserialize, Clone)]
struct PairMeta {
    base: String,
    target: String,
    algo: String,
    window_log: u32,
    level: u32,
    patch_size: u64,
    target_export_size: u64,
    export_sha256: String,
    compute_ms: u64,
    rank_ms: u64,
    candidates_ranked: usize,
    source: String,
    created_unix: u64,
    rejected: bool, // true: patch exceeded KEEP_RATIO, no blob kept
}

// ---------------------------------------------------------------- helpers

fn log(msg: &str) {
    eprintln!("[pifinder-differ] {msg}");
}

fn now_unix() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
}

/// "/nix/store/<32hash>-name" -> Some(("<32hash>", "name"))
fn split_store_path(p: &str) -> Option<(String, String)> {
    let base = p.strip_prefix("/nix/store/")?;
    if base.contains('/') {
        return None;
    }
    let (hash, name) = base.split_at_checked(32)?;
    let name = name.strip_prefix('-')?;
    if hash.len() != 32
        || !hash.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        || name.is_empty()
    {
        return None;
    }
    Some((hash.to_string(), name.to_string()))
}

/// Package stem: name with trailing version-ish components dropped.
/// "python3.13-numpy-2.1.3" -> "python3.13-numpy"
fn stem(name: &str) -> String {
    let mut parts: Vec<&str> = name.split('-').collect();
    while parts.len() > 1
        && parts
            .last()
            .and_then(|p| p.chars().next())
            .map(|c| c.is_ascii_digit())
            .unwrap_or(false)
    {
        parts.pop();
    }
    parts.join("-")
}

fn pair_key(base_hash: &str, target_hash: &str) -> String {
    format!("{base_hash}_{target_hash}")
}

async fn run(cmd: &mut Command) -> Result<std::process::Output> {
    let rendered = format!("{:?}", cmd.as_std());
    let out = cmd.output().await.with_context(|| format!("spawn {rendered}"))?;
    if !out.status.success() {
        bail!(
            "{rendered} failed ({}): {}",
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(out)
}

fn nix(args: &[&str]) -> Command {
    let mut c = Command::new("nix");
    c.args(["--extra-experimental-features", "nix-command"]);
    c.args(args);
    c.stdin(Stdio::null());
    c
}

async fn free_bytes(dir: &Path) -> Result<u64> {
    let out = run(Command::new("df")
        .args(["--output=avail", "-B1"])
        .arg(dir)
        .stdin(Stdio::null()))
    .await?;
    let s = String::from_utf8_lossy(&out.stdout);
    s.lines()
        .nth(1)
        .and_then(|l| l.trim().parse::<u64>().ok())
        .ok_or_else(|| anyhow!("unparseable df output"))
}

async fn sha256_file(p: &Path) -> Result<String> {
    let mut f = tokio::fs::File::open(p).await?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf).await?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}

// ---------------------------------------------------------------- nix ops

async fn path_is_local(p: &str) -> bool {
    Command::new("nix-store")
        .args(["--query", "--hash", p])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Make sure a path (and for toplevels: its closure) exists in the local store.
async fn ensure_local(app: &App, p: &str) -> Result<()> {
    if path_is_local(p).await {
        return Ok(());
    }
    let mut last = anyhow!("no substituters configured");
    for sub in &app.substituters {
        match run(&mut nix(&["copy", "--no-check-sigs", "--from", sub, p])).await {
            Ok(_) => return Ok(()),
            Err(e) => last = e.context(format!("nix copy from {sub}")),
        }
    }
    Err(last.context(format!("could not fetch {p}")))
}

async fn closure_paths(toplevel: &str) -> Result<Vec<String>> {
    let out = run(Command::new("nix-store")
        .args(["--query", "--requisites", toplevel])
        .stdin(Stdio::null()))
    .await?;
    Ok(String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty() && !l.ends_with(".drv"))
        .collect())
}

async fn export_path(store_path: &str, dest: &Path) -> Result<u64> {
    let f = std::fs::File::create(dest)?;
    let status = Command::new("nix-store")
        .args(["--export", store_path])
        .stdin(Stdio::null())
        .stdout(Stdio::from(f))
        .status()
        .await?;
    if !status.success() {
        bail!("nix-store --export {store_path} failed: {status}");
    }
    Ok(tokio::fs::metadata(dest).await?.len())
}

async fn zstd_patch(level: u32, base: &Path, target: &Path, out: &Path) -> Result<u64> {
    run(Command::new("zstd")
        .arg(format!("-{level}"))
        .arg(format!("--long={WINDOW_LOG}"))
        .arg("--single-thread")
        .arg("--force")
        .arg("--quiet")
        .arg(format!("--patch-from={}", base.display()))
        .arg(target)
        .arg("-o")
        .arg(out)
        .stdin(Stdio::null()))
    .await?;
    Ok(tokio::fs::metadata(out).await?.len())
}

// ---------------------------------------------------------------- compute

fn meta_path(app: &App, key: &str) -> PathBuf {
    app.meta_dir.join(format!("{key}.json"))
}

fn blob_path(app: &App, key: &str) -> PathBuf {
    app.blob_dir.join(format!("{key}.zst"))
}

fn load_meta(app: &App, key: &str) -> Option<PairMeta> {
    let raw = std::fs::read(meta_path(app, key)).ok()?;
    serde_json::from_slice(&raw).ok()
}

/// Compute the best patch for a job. Ranks candidate bases with a cheap zstd
/// pass, then compresses the winner at the tiered final level.
async fn compute(app: &App, job: &Job) -> Result<PairMeta> {
    let (t_hash, t_name) = split_store_path(&job.target)
        .ok_or_else(|| anyhow!("bad target {}", job.target))?;

    if free_bytes(&app.tmp_dir).await? < MIN_FREE_BYTES {
        bail!("low disk, skipping {t_name}");
    }

    let work = app.tmp_dir.join(&t_hash);
    tokio::fs::create_dir_all(&work).await?;
    // Whatever happens below, the workdir is removed at the end.
    let result = compute_inner(app, job, &t_hash, &work).await;
    let _ = tokio::fs::remove_dir_all(&work).await;
    result
}

async fn compute_inner(app: &App, job: &Job, t_hash: &str, work: &Path) -> Result<PairMeta> {
    let started = Instant::now();
    ensure_local(app, &job.target).await?;
    let target_export = work.join("target.export");
    let target_size = export_path(&job.target, &target_export).await?;

    // Rank: cheap patch against every candidate the device (or warmer) named.
    let rank_started = Instant::now();
    let mut ranked: Vec<(u64, String, PathBuf)> = Vec::new();
    for (i, base) in job.bases.iter().enumerate() {
        if split_store_path(base).is_none() {
            continue;
        }
        if ensure_local(app, base).await.is_err() {
            continue;
        }
        let base_export = work.join(format!("base{i}.export"));
        if export_path(base, &base_export).await.is_err() {
            continue;
        }
        let rank_out = work.join(format!("rank{i}.zst"));
        match zstd_patch(RANK_LEVEL, &base_export, &target_export, &rank_out).await {
            Ok(size) => ranked.push((size, base.clone(), base_export)),
            Err(e) => log(&format!("rank failed for {base}: {e:#}")),
        }
        let _ = tokio::fs::remove_file(&rank_out).await;
    }
    let rank_ms = rank_started.elapsed().as_millis() as u64;
    let candidates_ranked = ranked.len();
    ranked.sort_by_key(|(size, _, _)| *size);
    let (_, best_base, best_export) =
        ranked.into_iter().next().ok_or_else(|| anyhow!("no usable base"))?;
    let (b_hash, _) = split_store_path(&best_base).unwrap();

    // Final pass on the winner only.
    let level = if target_size < LARGE_TARGET_BYTES { FINAL_LEVEL_SMALL } else { FINAL_LEVEL_LARGE };
    let patch_tmp = work.join("patch.zst");
    let patch_size = zstd_patch(level, &best_export, &target_export, &patch_tmp).await?;
    let export_sha256 = sha256_file(&target_export).await?;

    let key = pair_key(&b_hash, t_hash);
    let rejected = (patch_size as f64) > (target_size as f64) * KEEP_RATIO;
    if rejected {
        let _ = tokio::fs::remove_file(&patch_tmp).await;
    } else {
        tokio::fs::rename(&patch_tmp, blob_path(app, &key)).await?;
    }

    let meta = PairMeta {
        base: best_base,
        target: job.target.clone(),
        algo: ALGO.into(),
        window_log: WINDOW_LOG,
        level,
        patch_size,
        target_export_size: target_size,
        export_sha256,
        compute_ms: started.elapsed().as_millis() as u64,
        rank_ms,
        candidates_ranked,
        source: job.source.into(),
        created_unix: now_unix(),
        rejected,
    };
    let tmp_meta = work.join("meta.json");
    tokio::fs::write(&tmp_meta, serde_json::to_vec_pretty(&meta)?).await?;
    tokio::fs::rename(&tmp_meta, meta_path(app, &key)).await?;
    Ok(meta)
}

// ---------------------------------------------------------------- workers

fn pop_job(app: &App) -> Option<Job> {
    if let Some(j) = app.demand.lock().unwrap().pop_front() {
        return Some(j);
    }
    app.warm.lock().unwrap().pop_front()
}

async fn worker_loop(app: Arc<App>) {
    loop {
        let Some(job) = pop_job(&app) else {
            tokio::time::sleep(Duration::from_millis(500)).await;
            continue;
        };
        let t = job.target.clone();
        match compute(&app, &job).await {
            Ok(m) => {
                app.jobs_done.fetch_add(1, Ordering::Relaxed);
                log(&format!(
                    "{} {} -> patch {} B / export {} B (level {}, {} ms, rank {} ms over {} bases){}",
                    job.source,
                    t,
                    m.patch_size,
                    m.target_export_size,
                    m.level,
                    m.compute_ms,
                    m.rank_ms,
                    m.candidates_ranked,
                    if m.rejected { " REJECTED" } else { "" },
                ));
            }
            Err(e) => {
                app.jobs_failed.fetch_add(1, Ordering::Relaxed);
                log(&format!("{} {t} FAILED: {e:#}", job.source));
            }
        }
        if let Some((h, _)) = split_store_path(&t) {
            app.inflight.lock().unwrap().remove(&h);
        }
    }
}

/// Queue a job unless the target is already computed against one of the given
/// bases, already inflight, or the queue is full. Returns what happened.
fn enqueue(app: &App, job: Job, demand: bool) -> &'static str {
    let Some((t_hash, _)) = split_store_path(&job.target) else {
        return "invalid";
    };
    for base in &job.bases {
        if let Some((b_hash, _)) = split_store_path(base) {
            if load_meta(app, &pair_key(&b_hash, &t_hash)).is_some() {
                return "exists";
            }
        }
    }
    if !app.inflight.lock().unwrap().insert(t_hash) {
        return "inflight";
    }
    let (q, cap) = if demand {
        (&app.demand, DEMAND_QUEUE_CAP)
    } else {
        (&app.warm, WARM_QUEUE_CAP)
    };
    let mut q = q.lock().unwrap();
    if q.len() >= cap {
        if let Some((h, _)) = split_store_path(&job.target) {
            app.inflight.lock().unwrap().remove(&h);
        }
        return "full";
    }
    q.push_back(job);
    "queued"
}

// ---------------------------------------------------------------- HTTP

#[derive(Deserialize)]
struct DeltaReq {
    target: String,
    bases: Vec<String>,
}

#[derive(Serialize)]
struct DeltaHit {
    algo: String,
    basis: Vec<String>,
    window_log: u32,
    url: String,
    size: u64,
    export_sha256: String,
}

async fn post_delta(State(app): State<Arc<App>>, Json(req): Json<DeltaReq>) -> Response {
    let Some((t_hash, _)) = split_store_path(&req.target) else {
        return (StatusCode::BAD_REQUEST, "target is not a store path").into_response();
    };
    let bases: Vec<String> =
        req.bases.iter().filter(|b| split_store_path(b).is_some()).cloned().collect();
    if bases.is_empty() {
        return (StatusCode::BAD_REQUEST, "no valid bases").into_response();
    }

    let mut all_rejected = true;
    for base in &bases {
        let (b_hash, _) = split_store_path(base).unwrap();
        let key = pair_key(&b_hash, &t_hash);
        if let Some(meta) = load_meta(&app, &key) {
            if meta.rejected {
                continue;
            }
            return Json(DeltaHit {
                algo: meta.algo,
                basis: vec![meta.base],
                window_log: meta.window_log,
                url: format!("/blobs/{key}.zst"),
                size: meta.patch_size,
                export_sha256: meta.export_sha256,
            })
            .into_response();
        }
        all_rejected = false;
    }
    if all_rejected {
        return StatusCode::NO_CONTENT.into_response();
    }

    match enqueue(&app, Job { target: req.target, bases, source: "demand" }, true) {
        "full" => StatusCode::SERVICE_UNAVAILABLE.into_response(),
        // queued | inflight | exists-under-other-base: tell the device to retry
        _ => (StatusCode::ACCEPTED, [("retry-after", "15")], "computing").into_response(),
    }
}

#[derive(Deserialize)]
struct WarmReq {
    base_toplevel: String,
    target_toplevel: String,
}

async fn post_warm(State(app): State<Arc<App>>, Json(req): Json<WarmReq>) -> Response {
    if split_store_path(&req.base_toplevel).is_none()
        || split_store_path(&req.target_toplevel).is_none()
    {
        return (StatusCode::BAD_REQUEST, "toplevels must be store paths").into_response();
    }
    let id = now_unix();
    app.warm_runs.lock().unwrap().push(WarmRun {
        id,
        base_toplevel: req.base_toplevel.clone(),
        target_toplevel: req.target_toplevel.clone(),
        state: "copying".into(),
        paired: 0,
        skipped_existing: 0,
        unpaired: 0,
        error: None,
        started_unix: id,
    });
    let app2 = app.clone();
    tokio::spawn(async move {
        let res = warm_run(&app2, id, &req.base_toplevel, &req.target_toplevel).await;
        let mut runs = app2.warm_runs.lock().unwrap();
        if let Some(r) = runs.iter_mut().find(|r| r.id == id) {
            if let Err(e) = res {
                r.state = "failed".into();
                r.error = Some(format!("{e:#}"));
            }
        }
    });
    (StatusCode::ACCEPTED, Json(serde_json::json!({ "warm_id": id }))).into_response()
}

async fn warm_run(app: &Arc<App>, id: u64, base_top: &str, target_top: &str) -> Result<()> {
    let set_state = |state: &str, paired: usize, skipped: usize, unpaired: usize| {
        let mut runs = app.warm_runs.lock().unwrap();
        if let Some(r) = runs.iter_mut().find(|r| r.id == id) {
            r.state = state.into();
            r.paired = paired;
            r.skipped_existing = skipped;
            r.unpaired = unpaired;
        }
    };

    ensure_local(app, base_top).await?;
    ensure_local(app, target_top).await?;
    set_state("pairing", 0, 0, 0);

    let base_closure = closure_paths(base_top).await?;
    let target_closure = closure_paths(target_top).await?;
    let base_set: HashSet<&String> = base_closure.iter().collect();

    // Index base closure by stem.
    let mut by_stem: HashMap<String, Vec<String>> = HashMap::new();
    for p in &base_closure {
        if let Some((_, name)) = split_store_path(p) {
            by_stem.entry(stem(&name)).or_default().push(p.clone());
        }
    }

    let (mut paired, mut skipped, mut unpaired) = (0usize, 0usize, 0usize);
    for target in &target_closure {
        if base_set.contains(target) {
            continue; // device already holds it — nix downloads nothing
        }
        let Some((_, name)) = split_store_path(target) else { continue };
        let Some(cands) = by_stem.get(&stem(&name)) else {
            unpaired += 1;
            continue;
        };
        let job = Job { target: target.clone(), bases: cands.clone(), source: "warm" };
        match enqueue(app, job, false) {
            "queued" => paired += 1,
            "exists" | "inflight" => skipped += 1,
            _ => unpaired += 1,
        }
    }
    set_state("queued", paired, skipped, unpaired);
    log(&format!(
        "warm {id}: {paired} queued, {skipped} already known, {unpaired} unpaired"
    ));
    Ok(())
}

async fn get_pairs(State(app): State<Arc<App>>) -> Response {
    let mut pairs: Vec<PairMeta> = Vec::new();
    if let Ok(rd) = std::fs::read_dir(&app.meta_dir) {
        for entry in rd.flatten() {
            if let Ok(raw) = std::fs::read(entry.path()) {
                if let Ok(m) = serde_json::from_slice::<PairMeta>(&raw) {
                    pairs.push(m);
                }
            }
        }
    }
    pairs.sort_by(|a, b| b.created_unix.cmp(&a.created_unix));
    let kept: Vec<&PairMeta> = pairs.iter().filter(|p| !p.rejected).collect();
    let total_patch: u64 = kept.iter().map(|p| p.patch_size).sum();
    let total_export: u64 = kept.iter().map(|p| p.target_export_size).sum();
    Json(serde_json::json!({
        "pairs": pairs,
        "summary": {
            "kept": kept.len(),
            "rejected": pairs.len() - kept.len(),
            "total_patch_bytes": total_patch,
            "total_target_export_bytes": total_export,
            "overall_ratio": if total_export > 0 {
                total_patch as f64 / total_export as f64
            } else { 0.0 },
        }
    }))
    .into_response()
}

async fn get_status(State(app): State<Arc<App>>) -> Response {
    Json(serde_json::json!({
        "demand_queue": app.demand.lock().unwrap().len(),
        "warm_queue": app.warm.lock().unwrap().len(),
        "inflight": app.inflight.lock().unwrap().len(),
        "jobs_done": app.jobs_done.load(Ordering::Relaxed),
        "jobs_failed": app.jobs_failed.load(Ordering::Relaxed),
        "warm_runs": *app.warm_runs.lock().unwrap(),
    }))
    .into_response()
}

async fn get_blob(State(app): State<Arc<App>>, AxPath(name): AxPath<String>) -> Response {
    // Names are "<32hash>_<32hash>.zst" — reject anything else.
    let ok = name.len() == 69
        && name.ends_with(".zst")
        && name[..65]
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_');
    if !ok {
        return StatusCode::NOT_FOUND.into_response();
    }
    match tokio::fs::File::open(app.blob_dir.join(&name)).await {
        Ok(f) => {
            let stream = tokio_util::io::ReaderStream::new(f);
            (
                [("content-type", "application/zstd")],
                axum::body::Body::from_stream(stream),
            )
                .into_response()
        }
        Err(_) => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn get_health() -> &'static str {
    "ok"
}

// ---------------------------------------------------------------- main

#[tokio::main]
async fn main() -> Result<()> {
    let listen = std::env::var("DIFFER_LISTEN").unwrap_or_else(|_| "127.0.0.1:8090".into());
    let state_dir = PathBuf::from(
        std::env::var("DIFFER_STATE_DIR").unwrap_or_else(|_| "/var/lib/pifinder-differ".into()),
    );
    let workers: usize = std::env::var("DIFFER_WORKERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| {
            std::thread::available_parallelism().map(|n| n.get().saturating_sub(1).max(1)).unwrap_or(1)
        });
    let substituters: Vec<String> = std::env::var("DIFFER_SUBSTITUTERS")
        .unwrap_or_else(|_| {
            "https://cache.pifinder.eu/pifinder https://cache.pifinder.eu/pifinder-release".into()
        })
        .split_whitespace()
        .map(String::from)
        .collect();

    let app = Arc::new(App {
        blob_dir: state_dir.join("blobs"),
        meta_dir: state_dir.join("meta"),
        tmp_dir: state_dir.join("tmp"),
        substituters,
        demand: Mutex::new(VecDeque::new()),
        warm: Mutex::new(VecDeque::new()),
        inflight: Mutex::new(HashSet::new()),
        warm_runs: Mutex::new(Vec::new()),
        jobs_done: AtomicU64::new(0),
        jobs_failed: AtomicU64::new(0),
    });
    for d in [&app.blob_dir, &app.meta_dir, &app.tmp_dir] {
        std::fs::create_dir_all(d)?;
    }
    // Stale workdirs from a previous crash.
    if let Ok(rd) = std::fs::read_dir(&app.tmp_dir) {
        for entry in rd.flatten() {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }

    for _ in 0..workers {
        tokio::spawn(worker_loop(app.clone()));
    }
    log(&format!("listening on {listen}, {workers} workers, state {}", state_dir.display()));

    let router = Router::new()
        .route("/health", get(get_health))
        .route("/status", get(get_status))
        .route("/pairs", get(get_pairs))
        .route("/delta", post(post_delta))
        .route("/warm", post(post_warm))
        .route("/blobs/:name", get(get_blob))
        .with_state(app);

    let listener = tokio::net::TcpListener::bind(&listen).await?;
    axum::serve(listener, router).await?;
    Ok(())
}
