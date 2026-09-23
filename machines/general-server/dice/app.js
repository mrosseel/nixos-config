import * as CANNON from "./vendor/cannon-es-0.20.0.min.js";

(function () {
  "use strict";

  var THREE = window.THREE;
  if (!THREE) {
    document.getElementById("fatal").classList.add("show");
    return;
  }
  window.diceTrayReady = true;

  /* ================================================================== *
   * Die shapes. Vertices are unnormalised; each is scaled so the
   * circumradius is 1, then multiplied by the die's radius. Faces are
   * index lists; winding is fixed later so every normal points outward.
   * ================================================================== */

  var PHI = (1 + Math.sqrt(5)) / 2;

  function d10Verts() {
    var v = [], i, b;
    for (i = 0; i < 10; i++) {
      b = i * Math.PI * 2 / 10;
      v.push([Math.cos(b), 0.105 * (i % 2 ? 1 : -1), Math.sin(b)]);
    }
    v.push([0, -1, 0]);
    v.push([0, 1, 0]);
    return v;
  }

  /* Each face is a kite: a pole first, then two ring vertices on the
     side of that pole with the ring vertex between them. The ring
     height of 0.105 puts the four points in one plane. */
  var D10_FACES = [
    [11, 5, 6, 7], [10, 4, 3, 2], [11, 1, 2, 3], [10, 0, 9, 8], [11, 7, 8, 9],
    [10, 8, 7, 6], [11, 9, 0, 1], [10, 2, 1, 0], [11, 3, 4, 5], [10, 6, 5, 4]
  ];

  var SHAPES = {
    tetra: {
      vertices: [[1, 1, 1], [-1, -1, 1], [-1, 1, -1], [1, -1, -1]],
      faces: [[1, 0, 2], [0, 1, 3], [2, 3, 0], [3, 2, 1]],
      label: 0.2, cornerLabels: true
    },
    cube: {
      vertices: [[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]],
      faces: [[4,5,6,7],[1,0,3,2],[5,1,2,6],[0,4,7,3],[7,6,2,3],[0,1,5,4]],
      label: 0.44, box: true, pips: true
    },
    octa: {
      vertices: [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]],
      faces: [[0,2,4],[2,1,4],[1,3,4],[3,0,4],[2,0,5],[1,2,5],[3,1,5],[0,3,5]],
      label: 0.30
    },
    trapez: { vertices: d10Verts(), faces: D10_FACES, label: 0.3, upFirst: true },
    dodeca: {
      vertices: [
        [0, 1/PHI, PHI], [0, 1/PHI, -PHI], [0, -1/PHI, PHI], [0, -1/PHI, -PHI],
        [PHI, 0, 1/PHI], [PHI, 0, -1/PHI], [-PHI, 0, 1/PHI], [-PHI, 0, -1/PHI],
        [1/PHI, PHI, 0], [1/PHI, -PHI, 0], [-1/PHI, PHI, 0], [-1/PHI, -PHI, 0],
        [1,1,1], [1,1,-1], [1,-1,1], [1,-1,-1], [-1,1,1], [-1,1,-1], [-1,-1,1], [-1,-1,-1]
      ],
      faces: [
        [2,14,4,12,0], [15,9,11,19,3], [16,10,17,7,6], [6,7,19,11,18],
        [6,18,2,0,16], [18,11,9,14,2], [1,17,10,8,13], [1,13,5,15,3],
        [13,8,12,4,5], [5,4,14,9,15], [0,12,8,10,16], [3,19,7,17,1]
      ],
      label: 0.40
    },
    icosa: {
      vertices: [
        [-1,PHI,0],[1,PHI,0],[-1,-PHI,0],[1,-PHI,0],[0,-1,PHI],[0,1,PHI],
        [0,-1,-PHI],[0,1,-PHI],[PHI,0,-1],[PHI,0,1],[-PHI,0,-1],[-PHI,0,1]
      ],
      faces: [
        [0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],
        [10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],
        [2,4,11],[6,2,10],[8,6,7],[9,8,1]
      ],
      label: 0.28
    }
  };

  /* Die types offered in the settings sheet. */
  var TYPES = [
    { id: "d4",   shape: "tetra",  faces: 4,  r: 0.92, range: "1 – 4",
      body: "#d8c49a", ink: "#2b2417", rough: 0.30 },
    { id: "d6",   shape: "cube",   faces: 6,  r: 0.85, range: "1 – 6",
      body: "#ece5d4", ink: "#1a1712", rough: 0.22 },
    { id: "d8",   shape: "octa",   faces: 8,  r: 0.92, range: "1 – 8",
      body: "#9dc6bd", ink: "#12261f", rough: 0.26 },
    { id: "d10",  shape: "trapez", faces: 10, r: 0.95, range: "1 – 10",
      body: "#b3a6cf", ink: "#1e1830", rough: 0.26 },
    { id: "d12",  shape: "dodeca", faces: 12, r: 0.95, range: "1 – 12",
      body: "#d59f7c", ink: "#2e1a10", rough: 0.28 },
    { id: "d20",  shape: "icosa",  faces: 20, r: 1.02, range: "1 – 20",
      body: "#c2564c", ink: "#f3e6d8", rough: 0.24 },
    { id: "d100", shape: "trapez", faces: 10, r: 0.95, range: "1 – 100", percentile: true,
      body: "#8fabc7", ink: "#141f2c", rough: 0.26 }
  ];

  /* The ones die of a d100 roll. It is marked 0 to 9, as a percentile
     pair is, and has the colour of its tens die, so the pair reads as
     one roll. It is not in the settings sheet. */
  var D100_UNITS = { id: "d100-units", shape: "trapez", faces: 10, r: 0.95, units: true,
    body: "#8fabc7", ink: "#141f2c", rough: 0.26 };

  var TYPE_BY_ID = {};
  TYPES.concat([D100_UNITS]).forEach(function (t) { TYPE_BY_ID[t.id] = t; });

  var MAX_DICE = 24;

  var BASE_LIN = 0.06, BASE_ANG = 0.09;

  /* Roll speed. The physics clock is multiplied by this, so the dice
     follow the same path at a different rate. Nothing about the throw or
     the resting face changes, which keeps every speed equally fair. */
  var SPEEDS = { slow: 0.5, normal: 1, fast: 1.9 };

  /* ============================== settings =========================== */

  var defaults = { counts: { d6: 2, d20: 1 }, sens: 16, speed: "normal", prompt: true, tilt: true, sfx: true };
  var settings = load();

  function load() {
    var out = JSON.parse(JSON.stringify(defaults));
    try {
      var raw = localStorage.getItem("pocket-dice-tray");
      if (!raw) return out;
      var s = JSON.parse(raw);
      if (s && s.counts) {
        out.counts = {};
        /* The limit is on the whole pool, as the stepper applies it. */
        var room = MAX_DICE;
        TYPES.forEach(function (t) {
          var n = Math.min(parseInt(s.counts[t.id], 10), room);
          if (n > 0) { out.counts[t.id] = n; room -= n; }
        });
      }
      if (s && isFinite(s.sens)) out.sens = Math.min(34, Math.max(6, s.sens));
      if (s && SPEEDS[s.speed]) out.speed = s.speed;
      if (s && typeof s.prompt === "boolean") out.prompt = s.prompt;
      if (s && typeof s.tilt === "boolean") out.tilt = s.tilt;
      if (s && typeof s.sfx === "boolean") out.sfx = s.sfx;
    } catch (e) {}
    return out;
  }

  function save() {
    try { localStorage.setItem("pocket-dice-tray", JSON.stringify(settings)); } catch (e) {}
  }

  function poolSize() {
    var n = 0;
    TYPES.forEach(function (t) { n += settings.counts[t.id] || 0; });
    return n;
  }

  /* =============================== random ============================ */

  var rndPool = null, rndAt = 0;
  function rnd() {
    if (!window.crypto || !window.crypto.getRandomValues) return Math.random();
    if (!rndPool || rndAt >= rndPool.length) {
      rndPool = new Uint32Array(256);
      window.crypto.getRandomValues(rndPool);
      rndAt = 0;
    }
    return rndPool[rndAt++] / 4294967296;
  }
  function sym() { return rnd() * 2 - 1; }

  /* ============================ die building ========================= */

  var V3 = THREE.Vector3;

  /* Normalises vertices, fixes winding, returns geometry + physics data. */
  function prepareShape(spec) {
    if (spec._ready) return spec._ready;

    var maxLen = 0;
    var verts = spec.vertices.map(function (v) {
      var p = new V3(v[0], v[1], v[2]);
      maxLen = Math.max(maxLen, p.length());
      return p;
    });
    verts.forEach(function (p) { p.multiplyScalar(1 / maxLen); });

    var faces = spec.faces.map(function (f) {
      var idx = f.slice();
      var c = new V3();
      idx.forEach(function (i) { c.add(verts[i]); });
      c.multiplyScalar(1 / idx.length);
      var n = new V3().subVectors(verts[idx[1]], verts[idx[0]])
                      .cross(new V3().subVectors(verts[idx[2]], verts[idx[0]]))
                      .normalize();
      /* Reverse the winding but keep the first vertex first: the d10
         names its pole there, and the numeral points at it. */
      if (n.dot(c) < 0) { idx = [idx[0]].concat(idx.slice(1).reverse()); n.negate(); }

      /* The texture axes on the face. u runs across the face and w is
         the "up" of the numeral. On a triangle, u aims at a corner. On
         the d6 that turned every face 45 degrees, which is why the 5
         came out as a diamond and the 6 as two diagonals, so a square
         face aims at the middle of an edge. A kite points its numeral
         at the pole, as a real d10 does. */
      var u, w;
      if (spec.upFirst) {
        w = new V3().subVectors(verts[idx[0]], c);
        u = new V3().crossVectors(w, n).normalize();
      } else {
        u = spec.box
          ? new V3().addVectors(verts[idx[0]], verts[idx[1]]).multiplyScalar(0.5).sub(c).normalize()
          : new V3().subVectors(verts[idx[0]], c).normalize();
      }
      w = new V3().crossVectors(n, u).normalize();

      /* Corners in face coordinates, scaled to fit the atlas cell. A
         triangle or kite fits the circle that holds it. A square fits
         edge to edge, so the pips land where they are painted. */
      var flat = idx.map(function (i) {
        var d = new V3().subVectors(verts[i], c);
        return [d.dot(u), d.dot(w)];
      });
      var maxR = 0;
      flat.forEach(function (p) {
        maxR = spec.box
          ? Math.max(maxR, Math.abs(p[0]), Math.abs(p[1]))
          : Math.max(maxR, Math.hypot(p[0], p[1]));
      });
      var corners = flat.map(function (p) { return [p[0] / maxR, p[1] / maxR]; });

      return { idx: idx, centroid: c, normal: n, corners: corners };
    });

    spec._ready = { verts: verts, faces: faces };
    return spec._ready;
  }

  /* Pairs opposite faces so they sum to faces+1, the way real dice do. */
  function faceValues(faces, n) {
    var values = new Array(faces.length);
    var v = 1;
    for (var i = 0; i < faces.length; i++) {
      if (values[i] != null) continue;
      var best = -1, bestDot = 2;
      for (var j = 0; j < faces.length; j++) {
        if (j === i || values[j] != null) continue;
        var d = faces[i].normal.dot(faces[j].normal);
        if (d < bestDot) { bestDot = d; best = j; }
      }
      values[i] = v;
      if (best >= 0) values[best] = n + 1 - v;
      v++;
    }
    return values;
  }

  var PIPS = {
    1: [[0, 0]],
    2: [[-1, -1], [1, 1]],
    3: [[-1, -1], [0, 0], [1, 1]],
    4: [[-1, -1], [1, -1], [-1, 1], [1, 1]],
    5: [[-1, -1], [1, -1], [0, 0], [-1, 1], [1, 1]],
    6: [[-1, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [1, 1]]
  };

  /* The marks on each face. Most dice carry one numeral per face. The
     d4 carries the number of each corner near that corner, so the
     result reads on every visible face. */
  function faceLabels(type, kit, ready) {
    if (kit.vertexValues) {
      return ready.faces.map(function (f) {
        return f.idx.map(function (vi, k) {
          return { text: String(kit.vertexValues[vi]), at: f.corners[k] };
        });
      });
    }
    return kit.values.map(function (v) {
      if (type.percentile) { var t = (v % 10) * 10; return t < 10 ? "0" + t : String(t); }
      if (type.units) return String(v % 10);
      return v;
    });
  }

  /* Paints one atlas cell per face: body colour plus the numeral. */
  function buildAtlas(type, labels, spec) {
    var n = labels.length;
    var cols = Math.ceil(Math.sqrt(n));
    var rows = Math.ceil(n / cols);
    var cell = 192;
    var cv = document.createElement("canvas");
    cv.width = cols * cell;
    cv.height = rows * cell;
    var c = cv.getContext("2d");

    c.fillStyle = type.body;
    c.fillRect(0, 0, cv.width, cv.height);

    c.textAlign = "center";
    c.textBaseline = "middle";

    for (var i = 0; i < n; i++) {
      var cx = (i % cols) * cell + cell / 2;
      var cy = Math.floor(i / cols) * cell + cell / 2;

      /* soft centre sheen so faces are not perfectly flat colour */
      var g = c.createRadialGradient(cx - cell * 0.15, cy - cell * 0.18, cell * 0.05,
                                     cx, cy, cell * 0.62);
      g.addColorStop(0, "rgba(255,255,255,0.16)");
      g.addColorStop(1, "rgba(0,0,0,0.10)");
      c.fillStyle = g;
      c.fillRect(cx - cell / 2, cy - cell / 2, cell, cell);

      var label = labels[i];
      c.fillStyle = type.ink;

      if (spec.pips && PIPS[label]) {
        var off = cell * 0.16, pr = cell * 0.052;
        PIPS[label].forEach(function (p) {
          c.beginPath();
          c.arc(cx + p[0] * off, cy + p[1] * off, pr, 0, Math.PI * 2);
          c.fill();
        });
        continue;
      }

      var fill = ATLAS_FILL;
      var marks = Array.isArray(label)
        ? label.map(function (m) {
            /* 58% of the way to the corner, top of the digit toward it */
            var dx = m.at[0] * 0.58 * fill * cell / 2, dy = -m.at[1] * 0.58 * fill * cell / 2;
            return { text: m.text, x: cx + dx, y: cy + dy, rot: Math.atan2(dx, -dy) };
          })
        : [{ text: String(label), x: cx, y: cy, rot: 0 }];

      marks.forEach(function (m) {
        var size = cell * spec.label * (m.text.length > 1 ? 0.78 : 1);
        c.save();
        c.translate(m.x, m.y);
        c.rotate(m.rot);
        c.font = "700 " + size.toFixed(1) + "px Cinzel, Georgia, serif";
        c.fillText(m.text, 0, 0);
        if (m.text === "6" || m.text === "9") {
          c.fillRect(-size * 0.3, size * 0.46, size * 0.6, Math.max(2, size * 0.07));
        }
        c.restore();
      });
    }

    var tex = new THREE.CanvasTexture(cv);
    tex.anisotropy = 4;
    tex.encoding = THREE.sRGBEncoding;
    return { texture: tex, cols: cols, rows: rows };
  }

  /* How much of its atlas cell a face covers. */
  var ATLAS_FILL = 0.97;

  /* Builds the mesh geometry, mapping each face into its atlas cell. */
  function buildGeometry(ready, radius, atlas) {
    var pos = [], uv = [], nor = [];
    var faces = ready.faces;
    var cw = 1 / atlas.cols, ch = 1 / atlas.rows;

    faces.forEach(function (f, fi) {
      var pts = f.idx.map(function (i) {
        return ready.verts[i].clone().multiplyScalar(radius);
      });
      var n = f.normal;

      var col = fi % atlas.cols, row = Math.floor(fi / atlas.cols);
      var ucx = (col + 0.5) * cw;
      var vcy = 1 - (row + 0.5) * ch;

      function uvOf(p) {
        return [
          ucx + p[0] * (cw / 2) * ATLAS_FILL,
          vcy + p[1] * (ch / 2) * ATLAS_FILL
        ];
      }

      for (var k = 1; k < pts.length - 1; k++) {
        var tri = [0, k, k + 1];
        for (var t = 0; t < 3; t++) {
          var p = pts[tri[t]], q = uvOf(f.corners[tri[t]]);
          pos.push(p.x, p.y, p.z);
          uv.push(q[0], q[1]);
          nor.push(n.x, n.y, n.z);
        }
      }
    });

    var geo = new THREE.BufferGeometry();
    geo.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
    geo.setAttribute("normal", new THREE.Float32BufferAttribute(nor, 3));
    return geo;
  }

  function buildPhysicsShape(ready, radius, spec) {
    if (spec.box) {
      var h = radius / Math.sqrt(3);
      return new CANNON.Box(new CANNON.Vec3(h, h, h));
    }
    var pts = ready.verts.map(function (v) {
      return new CANNON.Vec3(v.x * radius, v.y * radius, v.z * radius);
    });
    var faces = ready.faces.map(function (f) { return f.idx.slice(); });
    return new CANNON.ConvexPolyhedron({ vertices: pts, faces: faces });
  }

  /* One kit per die type: geometry, material, physics shape, face values. */
  var kits = {};
  function kitFor(type) {
    if (kits[type.id]) return kits[type.id];

    var spec = SHAPES[type.shape];
    var ready = prepareShape(spec);
    var values = faceValues(ready.faces, type.faces);
    /* A d4 is read at the corner that points up, so its values sit on
       the vertices: vertex i shows i + 1. */
    var vertexValues = spec.cornerLabels
      ? ready.verts.map(function (v, i) { return i + 1; })
      : null;
    var labels = faceLabels(type, { values: values, vertexValues: vertexValues }, ready);

    var atlas = buildAtlas(type, labels, spec);
    var geo = buildGeometry(ready, type.r, atlas);
    var mat = new THREE.MeshPhysicalMaterial({
      map: atlas.texture,
      roughness: type.rough,
      metalness: 0.0,
      clearcoat: 1.0,
      clearcoatRoughness: 0.08,
      reflectivity: 0.55,
      envMap: envTex,
      envMapIntensity: 1.15,
      flatShading: true
    });

    kits[type.id] = {
      geometry: geo,
      material: mat,
      shape: buildPhysicsShape(ready, type.r, spec),
      normals: ready.faces.map(function (f) { return f.normal.clone(); }),
      values: values,
      vertexValues: vertexValues,
      corners: vertexValues ? ready.verts.map(function (v) { return v.clone(); }) : null,
      ready: ready,
      spec: spec,
      mass: 0.32 * type.r * type.r * type.r
    };
    return kits[type.id];
  }

  /* ============================== three.js =========================== */

  var canvas = document.getElementById("stage");
  var renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.outputEncoding = THREE.sRGBEncoding;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.06;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  var scene = new THREE.Scene();
  scene.background = new THREE.Color("#0a1815");

  var camera = new THREE.PerspectiveCamera(42, 1, 0.5, 200);

  /* Environment: a painted studio strip light, so highlights sweep the
     facets as the dice tumble. */
  var envTex = (function () {
    var cv = document.createElement("canvas");
    cv.width = 1024; cv.height = 512;
    var c = cv.getContext("2d");
    var g = c.createLinearGradient(0, 0, 0, 512);
    g.addColorStop(0.00, "#dfeaf2");
    g.addColorStop(0.42, "#8fa3a8");
    g.addColorStop(0.52, "#33443f");
    g.addColorStop(1.00, "#0c1a16");
    c.fillStyle = g;
    c.fillRect(0, 0, 1024, 512);

    function blob(x, y, rx, ry, alpha) {
      var rg = c.createRadialGradient(x, y, 0, x, y, Math.max(rx, ry));
      rg.addColorStop(0, "rgba(255,255,255," + alpha + ")");
      rg.addColorStop(1, "rgba(255,255,255,0)");
      c.save();
      c.translate(x, y);
      c.scale(rx / Math.max(rx, ry), ry / Math.max(rx, ry));
      c.translate(-x, -y);
      c.fillStyle = rg;
      c.fillRect(x - rx, y - ry, rx * 2, ry * 2);
      c.restore();
    }
    blob(250, 120, 300, 90, 0.95);
    blob(760, 150, 200, 70, 0.7);
    blob(520, 60, 420, 60, 0.5);

    var t = new THREE.CanvasTexture(cv);
    t.mapping = THREE.EquirectangularReflectionMapping;
    t.encoding = THREE.sRGBEncoding;
    return t;
  })();

  scene.add(new THREE.HemisphereLight(0xd8e6ea, 0x14302a, 0.55));

  var key = new THREE.DirectionalLight(0xfff3dd, 1.55);
  key.position.set(6, 16, 5);
  key.castShadow = true;
  key.shadow.mapSize.set(768, 768);
  key.shadow.camera.near = 2;
  key.shadow.camera.far = 46;
  key.shadow.bias = -0.0016;
  key.shadow.radius = 3;
  scene.add(key);

  var rim = new THREE.DirectionalLight(0xc9a227, 0.5);
  rim.position.set(-8, 7, -6);
  scene.add(rim);

  /* Felt floor, painted once into a canvas texture. */
  var feltTex = (function () {
    var s = 512;
    var cv = document.createElement("canvas");
    cv.width = cv.height = s;
    var c = cv.getContext("2d");
    c.fillStyle = "#1a352d";
    c.fillRect(0, 0, s, s);
    for (var i = 0; i < 26000; i++) {
      var a = Math.random();
      c.fillStyle = a > 0.5
        ? "rgba(255,255,255," + (0.012 + a * 0.03) + ")"
        : "rgba(0,0,0," + (0.02 + a * 0.07) + ")";
      c.fillRect(Math.random() * s, Math.random() * s, 1.6, 1.6);
    }
    var t = new THREE.CanvasTexture(cv);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(6, 6);
    t.encoding = THREE.sRGBEncoding;
    return t;
  })();

  var floor = new THREE.Mesh(
    new THREE.PlaneGeometry(1, 1),
    new THREE.MeshStandardMaterial({ map: feltTex, roughness: 0.96, metalness: 0 })
  );
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  scene.add(floor);

  /* Wooden rim drawn as four thin boxes just outside the play area. */
  var rimMat = new THREE.MeshStandardMaterial({ color: "#2a1a0d", roughness: 0.82, metalness: 0.0 });
  var rims = [];
  for (var ri = 0; ri < 4; ri++) {
    var m = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), rimMat);
    m.castShadow = true;
    m.receiveShadow = true;
    scene.add(m);
    rims.push(m);
  }

  /* ============================== physics ============================ */

  var world = new CANNON.World();
  world.gravity.set(0, -32, 0);
  world.broadphase = new CANNON.NaiveBroadphase();
  world.solver.iterations = 12;
  world.allowSleep = false;

  var matDie = new CANNON.Material("die");
  var matTray = new CANNON.Material("tray");
  world.addContactMaterial(new CANNON.ContactMaterial(matDie, matDie, {
    friction: 0.14, restitution: 0.30
  }));
  world.addContactMaterial(new CANNON.ContactMaterial(matDie, matTray, {
    friction: 0.22, restitution: 0.38
  }));

  var walls = [];
  function makeWall(axis, angle) {
    var b = new CANNON.Body({ mass: 0, shape: new CANNON.Plane(), material: matTray });
    if (angle) b.quaternion.setFromAxisAngle(axis, angle);
    world.addBody(b);
    walls.push(b);
    return b;
  }
  var X = new CANNON.Vec3(1, 0, 0), Y = new CANNON.Vec3(0, 1, 0);
  var wFloor = makeWall(X, -Math.PI / 2);
  var wCeil  = makeWall(X, Math.PI / 2);
  var wLeft  = makeWall(Y, Math.PI / 2);
  var wRight = makeWall(Y, -Math.PI / 2);
  var wBack  = makeWall(Y, 0);
  var wFront = makeWall(Y, Math.PI);

  var halfW = 5, halfD = 9, ceilY = 14;
  var RIM_TH = 0.9;

  /* The tray's short side, in world units. A d6 is 1.7 across, so this
     sets how big the dice look: bigger number, smaller dice. */
  var TARGET_MIN_HALF = 5.6;
  /* Measure the frame at the height of a die's top face, not at the
     table. A die resting by the wall is a body, not a point, and at
     table height it would hang over the edge of the screen. */
  var CLEAR_Y = 1.7;

  var barEl = document.querySelector(".bar");
  var readoutEl = document.querySelector(".readout");

  /* Visible play area between the top bar and the readout, on the
     clearance plane, for the camera at the given distance. */
  function measureArea(dist) {
    camera.position.set(0, dist * 0.985, dist * 0.17);
    camera.lookAt(0, 0, 0);
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld();

    var h = window.innerHeight;
    var topPx = (barEl ? barEl.offsetHeight : 64) + 8;
    var botPx = (readoutEl ? readoutEl.offsetHeight : 108) + 8;
    var nTop = Math.max(-0.9, 1 - 2 * topPx / h);
    var nBot = Math.min(0.9, -1 + 2 * botPx / h);

    var ray = new THREE.Raycaster();
    var plane = new THREE.Plane(new V3(0, 1, 0), -CLEAR_Y);
    var minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    [[-1, nBot], [1, nBot], [-1, nTop], [1, nTop]].forEach(function (c) {
      ray.setFromCamera({ x: c[0], y: c[1] }, camera);
      var hit = new V3();
      if (ray.ray.intersectPlane(plane, hit)) {
        minX = Math.min(minX, hit.x); maxX = Math.max(maxX, hit.x);
        minZ = Math.min(minZ, hit.z); maxZ = Math.max(maxZ, hit.z);
      }
    });
    if (!isFinite(minX)) return null;
    return {
      halfW: Math.min(Math.abs(minX), Math.abs(maxX)),
      halfD: Math.min(Math.abs(minZ), Math.abs(maxZ))
    };
  }

  function layoutTray() {
    var w = window.innerWidth, h = window.innerHeight;
    camera.aspect = w / h;

    /* Pull the camera back until the short side of the visible area is
       TARGET_MIN_HALF, so dice read the same size in any orientation.
       Two passes: the mapping is close to linear in distance. */
    var vFov = camera.fov * Math.PI / 180;
    var dist = TARGET_MIN_HALF / Math.tan(vFov / 2) + CLEAR_Y;
    var area = null;
    for (var pass = 0; pass < 3; pass++) {
      area = measureArea(dist);
      if (!area) break;
      var short = Math.min(area.halfW, area.halfD);
      if (short < 0.01) break;
      dist *= TARGET_MIN_HALF / short;
    }
    area = measureArea(dist) || { halfW: 4.9, halfD: 9 };

    /* Hold back a rim's width plus a margin, so the wooden edge of the
       tray is inside the picture on all four sides instead of just off
       it. RIM_TH must match the rim boxes built below. */
    halfW = Math.max(2.4, area.halfW - RIM_TH - 0.25);
    halfD = Math.max(3.0, area.halfD - RIM_TH - 0.25);

    wFloor.position.set(0, 0, 0);
    wCeil.position.set(0, ceilY, 0);
    wLeft.position.set(-halfW, 0, 0);
    wRight.position.set(halfW, 0, 0);
    wBack.position.set(0, 0, -halfD);
    wFront.position.set(0, 0, halfD);

    floor.scale.set(halfW * 2 + 4, halfD * 2 + 4, 1);
    feltTex.repeat.set(halfW * 0.7, halfD * 0.7);

    var th = RIM_TH, hgt = 1.5;
    rims[0].scale.set(th, hgt, halfD * 2 + th * 2);
    rims[0].position.set(-halfW - th / 2, hgt / 2 - 0.15, 0);
    rims[1].scale.set(th, hgt, halfD * 2 + th * 2);
    rims[1].position.set(halfW + th / 2, hgt / 2 - 0.15, 0);
    rims[2].scale.set(halfW * 2 + th * 2, hgt, th);
    rims[2].position.set(0, hgt / 2 - 0.15, -halfD - th / 2);
    rims[3].scale.set(halfW * 2 + th * 2, hgt, th);
    rims[3].position.set(0, hgt / 2 - 0.15, halfD + th / 2);

    var span = Math.max(halfW, halfD) + 3;
    key.shadow.camera.left = -span;
    key.shadow.camera.right = span;
    key.shadow.camera.top = span;
    key.shadow.camera.bottom = -span;
    key.shadow.camera.updateProjectionMatrix();

    renderer.setSize(w, h, false);
  }

  /* ================================ audio ============================ */

  var AC = window.AudioContext || window.webkitAudioContext;
  var actx = null, master = null, noiseBuf = null;
  var soundBudget = 0, soundBudgetAt = 0;

  function initAudio() {
    if (actx || !AC) return;
    actx = new AC();
    master = actx.createGain();
    master.gain.value = 0.85;
    master.connect(actx.destination);

    var len = Math.floor(actx.sampleRate * 0.3);
    noiseBuf = actx.createBuffer(1, len, actx.sampleRate);
    var data = noiseBuf.getChannelData(0);
    for (var i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  }

  function resumeAudio() {
    initAudio();
    if (actx && actx.state === "suspended") actx.resume();
  }

  /* One clack. `hard` is a die on a die or the rim; soft is the felt. */
  function clack(strength, size, hard) {
    if (!settings.sfx || !actx || actx.state !== "running") return;
    var now = actx.currentTime;
    var ms = performance.now();
    if (ms - soundBudgetAt > 60) { soundBudget = 0; soundBudgetAt = ms; }
    if (soundBudget >= 4) return;
    soundBudget++;

    var amp = Math.min(1, strength) ;
    amp = Math.pow(amp, 0.7) * (hard ? 0.55 : 0.3);
    if (amp < 0.012) return;

    var base = (hard ? 2500 : 900) / (0.55 + size);
    var dur = hard ? 0.075 + rnd() * 0.05 : 0.11 + rnd() * 0.05;

    var src = actx.createBufferSource();
    src.buffer = noiseBuf;
    src.playbackRate.value = 0.7 + rnd() * 0.7;

    var bp = actx.createBiquadFilter();
    bp.type = "bandpass";
    bp.frequency.value = base * (0.8 + rnd() * 0.45);
    bp.Q.value = hard ? 2.6 : 0.9;

    var hp = actx.createBiquadFilter();
    hp.type = "highpass";
    hp.frequency.value = hard ? 400 : 160;

    var g = actx.createGain();
    g.gain.setValueAtTime(0.0001, now);
    g.gain.linearRampToValueAtTime(amp, now + 0.0022);
    g.gain.exponentialRampToValueAtTime(0.0001, now + dur);

    src.connect(bp); bp.connect(hp); hp.connect(g); g.connect(master);
    src.start(now);
    src.stop(now + dur + 0.02);

    /* low body knock, so a big die sounds heavier than a small one */
    var osc = actx.createOscillator();
    var og = actx.createGain();
    osc.type = "triangle";
    var f0 = (hard ? 230 : 150) / (0.6 + size);
    osc.frequency.setValueAtTime(f0, now);
    osc.frequency.exponentialRampToValueAtTime(f0 * 0.55, now + 0.06);
    og.gain.setValueAtTime(0.0001, now);
    og.gain.linearRampToValueAtTime(amp * 0.5, now + 0.004);
    og.gain.exponentialRampToValueAtTime(0.0001, now + 0.085);
    osc.connect(og); og.connect(master);
    osc.start(now);
    osc.stop(now + 0.1);
  }

  /* ================================ dice ============================= */

  /* Shoemake's uniform random rotation. Three Euler angles drawn
     uniformly are NOT uniform over the rotation group: they bunch
     orientations near the poles, which biases how a die starts. */
  function randomOrientation(q) {
    var u1 = rnd(), t1 = rnd() * Math.PI * 2, t2 = rnd() * Math.PI * 2;
    var a = Math.sqrt(1 - u1), b = Math.sqrt(u1);
    q.set(a * Math.sin(t1), a * Math.cos(t1), b * Math.sin(t2), b * Math.cos(t2));
  }

  var entries = [];   /* one entry per die in the pool; d100 holds two */
  var allDice = [];

  function makeDie(type, tint) {
    var kit = kitFor(type);
    var mesh = new THREE.Mesh(kit.geometry, kit.material);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    scene.add(mesh);

    var body = new CANNON.Body({
      mass: kit.mass,
      shape: kit.shape,
      material: matDie,
      linearDamping: BASE_LIN,
      angularDamping: BASE_ANG
    });
    world.addBody(body);

    var die = { type: type, kit: kit, mesh: mesh, body: body, value: null, tint: tint || null };

    body.addEventListener("collide", function (e) {
      var c = e.contact;
      if (!c) return;
      var v = Math.abs(c.getImpactVelocityAlongNormal());
      if (v < 1.1) return;
      var hard = e.body && e.body.mass > 0;
      clack(v / 14, type.r, hard);
    });

    allDice.push(die);
    return die;
  }

  function destroyDie(die) {
    scene.remove(die.mesh);
    world.removeBody(die.body);
    var i = allDice.indexOf(die);
    if (i >= 0) allDice.splice(i, 1);
  }

  function buildPool() {
    entries.slice().forEach(function (en) { en.dice.forEach(destroyDie); });
    entries = [];

    TYPES.forEach(function (t) {
      var n = settings.counts[t.id] || 0;
      for (var i = 0; i < n; i++) {
        var dice = t.percentile
          ? [makeDie(t), makeDie(D100_UNITS)]
          : [makeDie(t)];
        entries.push({ type: t, dice: dice, value: null });
      }
    });

    if (entries.length) scatter();
    setReadout();
  }

  /* Drops the dice in place without a throw, for the opening view. */
  function scatter() {
    allDice.forEach(function (d, i) {
      d.body.position.set(
        sym() * Math.max(0.5, halfW - d.type.r - 0.4),
        d.type.r + 0.02 + i * 0.001,
        sym() * Math.max(0.5, halfD - d.type.r - 2.2)
      );
      randomOrientation(d.body.quaternion);
      d.body.velocity.set(0, 0, 0);
      d.body.angularVelocity.set(0, 0, 0);
    });
    /* Every die gets a fresh random facing, so this counts as a roll. */
    beginRoll("throw");
  }

  /* ============================== throwing =========================== */

  var rolling = false;
  var settleFrames = 0;
  var rollStart = 0;
  /* "throw" when the dice got a fresh random facing, "nudge" when they
     were only pushed. A knock leaves a d6 on the same face 99% of the
     time, so a nudge must not look like a new roll. */
  var rollKind = "throw";
  var reseats = 0;

  function beginRoll(kind) {
    if (kind === "throw" || !rolling) rollKind = kind;
    rolling = true;
    settleFrames = 0;
    reseats = 0;
    rollStart = performance.now();
    wake();
    setReadout();
  }

  function throwDice(dirX, dirZ, power) {
    if (!entries.length) { openSheet(); return; }
    resumeAudio();
    hideHint();

    var p = power == null ? 1 : Math.min(2.4, power);

    /* Each die is thrown from where it already lies. Teleporting them to
       the edge first made every shake look like a cut to a new shot. */
    allDice.forEach(function (d) {
      d.value = null;
      var b = d.body;

      /* Without a swipe direction, each die picks its own, so a tight
         cluster spreads out instead of moving as one block. */
      var ax = dirX || 0, az = dirZ || 0;
      if (!ax && !az) {
        var a = rnd() * Math.PI * 2;
        ax = Math.cos(a);
        az = Math.sin(a);
      }
      var spread = 0.5;
      ax += sym() * spread;
      az += sym() * spread;

      /* The die keeps its place but not its facing. Thrown from the face
         it was already showing, it keeps a trace of it: over 4000 results
         a Fast roll repeated the previous face 20.1% of the time against
         the 16.7% chance allows, and the transition matrix failed too,
         chi2 52 against a 37.7 cutoff. Spinning the dice twice as hard
         did not shift it. Re-seating here did, to 16.95% and chi2 27.6.
         The die does not move, so this is not the jump that moving the
         position was. */
      randomOrientation(b.quaternion);


      /* Throw speed follows the tray, so a big screen is not sluggish. */
      var sp = (0.55 + rnd() * 0.55) * halfD * p;
      b.velocity.x += ax * sp;
      b.velocity.z += az * sp;
      b.velocity.y += (7 + rnd() * 6) * p;
      b.angularVelocity.x += sym() * 30 * p;
      b.angularVelocity.y += sym() * 30 * p;
      b.angularVelocity.z += sym() * 30 * p;

      /* Impulses stack, so a fast repeat shake could otherwise build a
         speed the walls cannot hold. */
      var vmax = halfD * 3.2;
      var v = b.velocity;
      var vm = Math.hypot(v.x, v.y, v.z);
      if (vm > vmax) {
        var f = vmax / vm;
        v.x *= f; v.y *= f; v.z *= f;
      }

      b.wakeUp();
    });

    beginRoll("throw");
    if (navigator.vibrate) { try { navigator.vibrate(18); } catch (e) {} }
  }

  function quatOf(die) {
    var q = die.body.quaternion;
    return new THREE.Quaternion(q.x, q.y, q.z, q.w);
  }

  /* Reads the face pointing at the ceiling once a die has stopped. A d4
     is read at the corner that points up. */
  function readDie(die) {
    var quat = quatOf(die);
    var best = -Infinity, bestIdx = 0, i, y;
    if (die.kit.vertexValues) {
      for (i = 0; i < die.kit.corners.length; i++) {
        y = die.kit.corners[i].clone().applyQuaternion(quat).y;
        if (y > best) { best = y; bestIdx = i; }
      }
      return die.kit.vertexValues[bestIdx];
    }
    for (i = 0; i < die.kit.normals.length; i++) {
      y = die.kit.normals[i].clone().applyQuaternion(quat).y;
      if (y > best) { best = y; bestIdx = i; }
    }
    return die.kit.values[bestIdx];
  }

  /* How flat a die lies: 1 when a face is on the floor. Below
     COCKED_LIMIT the die leans on a wall or on another die. */
  var COCKED_LIMIT = Math.cos(10 * Math.PI / 180);
  function flatness(die) {
    var quat = quatOf(die), best = -Infinity;
    for (var i = 0; i < die.kit.normals.length; i++) {
      best = Math.max(best, -die.kit.normals[i].clone().applyQuaternion(quat).y);
    }
    return best;
  }

  /* A leaning die gets a fresh random facing and a small hop toward the
     middle of the tray, the way a player rerolls a cocked die. In a
     headless test of 15000 d6 results, dice tilted more than 25 degrees
     fell from 4.3% to 0.1%. A plain knock without the fresh facing
     skewed the d6 counts, chi2 12.5 against an 11.07 cutoff. */
  function reseat(die) {
    var b = die.body;
    randomOrientation(b.quaternion);
    b.position.y = Math.max(b.position.y, die.type.r + 0.4);
    b.velocity.set(
      -Math.sign(b.position.x) * (1 + rnd() * 2) + sym(),
      5 + rnd() * 3,
      -Math.sign(b.position.z) * (1 + rnd() * 2) + sym()
    );
    b.angularVelocity.set(sym() * 14, sym() * 14, sym() * 14);
    b.wakeUp();
  }

  function readAll() {
    entries.forEach(function (en) {
      en.dice.forEach(function (d) { d.value = readDie(d); });
      if (en.type.percentile) {
        var tens = en.dice[0].value % 10;
        var units = en.dice[1].value % 10;
        var v = tens * 10 + units;
        en.value = v === 0 ? 100 : v;
      } else {
        en.value = en.dice[0].value;
      }
    });
  }

  /* =============================== readout =========================== */

  var totalValue = document.getElementById("totalValue");
  var totalLabel = document.getElementById("totalLabel");
  var breakdown = document.getElementById("breakdown");

  function setReadout() {
    if (!entries.length) {
      totalLabel.textContent = "Empty tray";
      totalValue.textContent = "—";
      totalValue.className = "total-value muted";
      breakdown.innerHTML = "";
      return;
    }
    if (rolling) {
      totalLabel.textContent = "Total";
      totalValue.textContent = "rolling";
      totalValue.className = "total-value muted";
      breakdown.innerHTML = "";
      return;
    }
    var sum = 0, html = "";
    entries.forEach(function (en) {
      if (en.value == null) return;
      sum += en.value;
      var cls = "chip";
      if (en.type.id === "d20" && en.value === 20) cls += " crit";
      if (en.type.id === "d20" && en.value === 1) cls += " fumble";
      html += '<span class="' + cls + '"><span class="die-tag">' + en.type.id +
              "</span>" + en.value + "</span>";
    });
    if (rollKind === "nudge") {
      totalLabel.textContent = "Nudged, not a roll";
      totalValue.className = "total-value stale";
    } else {
      totalLabel.textContent = entries.length === 1 ? "Result" : "Total of " + entries.length;
      totalValue.className = "total-value";
    }
    totalValue.textContent = String(sum);
    breakdown.innerHTML = html;
  }

  /* ================================ loop ============================= */

  /* ---------------------------- quality ----------------------------- *
   * Phones vary far more than desktops. Rather than guess from the user
   * agent, render, measure, and shed the expensive parts if the frame
   * rate cannot pay for them. Downgrade only, so it settles instead of
   * oscillating between two levels.
   * ------------------------------------------------------------------ */

  var quality = 2;
  var qFrames = 0, qStart = 0;

  function setClearcoat(v) {
    Object.keys(kits).forEach(function (id) {
      var m = kits[id].material;
      if (m.clearcoat === v) return;
      m.clearcoat = v;
      m.needsUpdate = true;
    });
  }

  function applyQuality() {
    var dpr = window.devicePixelRatio || 1;
    if (quality >= 2) {
      renderer.setPixelRatio(Math.min(dpr, 1.5));
      renderer.shadowMap.enabled = true;
      key.shadow.mapSize.set(768, 768);
      key.castShadow = true;
      setClearcoat(1.0);
    } else if (quality === 1) {
      renderer.setPixelRatio(Math.min(dpr, 1.1));
      renderer.shadowMap.enabled = true;
      key.shadow.mapSize.set(512, 512);
      key.castShadow = true;
      setClearcoat(0.35);
    } else {
      renderer.setPixelRatio(1);
      renderer.shadowMap.enabled = false;
      key.castShadow = false;
      setClearcoat(0);
      world.solver.iterations = 9;
    }
    if (key.shadow.map) { key.shadow.map.dispose(); key.shadow.map = null; }
    renderer.shadowMap.needsUpdate = true;
    renderer.setSize(window.innerWidth, window.innerHeight, false);
    wake();
  }

  /* Sampled only while dice are moving: a still tray is cheap and would
     otherwise make every device look fast. */
  function sampleFps(now) {
    if (quality === 0 || !rolling) { qFrames = 0; qStart = now; return; }
    if (!qStart) { qStart = now; qFrames = 0; return; }
    qFrames++;
    var span = now - qStart;
    if (span < 900) return;
    var fps = qFrames * 1000 / span;
    qFrames = 0;
    qStart = now;
    if (fps < 45) {
      quality--;
      applyQuality();
    }
  }

  var lastTime = performance.now();

  /* Idle: a still tray is neither simulated nor drawn, which saves the
     battery of a phone that lies on the table. `quiet` counts frames
     with no motion. wake() runs the loop again. */
  var QUIET_IDLE = 30;
  var quiet = 0;
  var restGravity = { x: 0, z: 0 };
  var shoveFrames = 0;

  function wake() { quiet = 0; }

  function tick(now) {
    requestAnimationFrame(tick);
    var gap = now - lastTime;
    lastTime = now;

    /* A hidden tab gets no frames. Without this, a roll that was in the
       air when the tab was hidden passes its time limit on the first
       frame back and is read in mid air. The FPS sample would also see
       almost 0 fps and lower the quality for good. */
    if (gap > 250) {
      rollStart += gap;
      qStart = 0;
    }
    var dt = Math.min(0.05, gap / 1000);

    if (!rolling && quiet > QUIET_IDLE) {
      /* A tilt of the phone can start the dice sliding. */
      var g = world.gravity;
      if (Math.abs(g.x - restGravity.x) + Math.abs(g.z - restGravity.z) < 0.8) {
        qStart = 0;   /* idle frames are not a measure of speed */
        return;
      }
      quiet = 0;
    }

    /* A slow roll needs no extra substeps; a fast one asks the solver for
       more simulated time per frame, so the cap has to follow it. */
    var scale = SPEEDS[settings.speed] || 1;
    world.step(1 / 60, dt * scale, Math.ceil(dt * scale * 60) + 1);

    var moving = false, shoved = false;
    for (var i = 0; i < allDice.length; i++) {
      var d = allDice[i];
      var b = d.body;

      d.mesh.position.set(b.position.x, b.position.y, b.position.z);
      d.mesh.quaternion.set(b.quaternion.x, b.quaternion.y, b.quaternion.z, b.quaternion.w);
      var lin = b.velocity.lengthSquared(), ang = b.angularVelocity.lengthSquared();
      if (lin > 0.02 || ang > 0.09) moving = true;
      if (lin > 0.5 || ang > 1) shoved = true;
    }

    if (rolling) {
      if (!moving) settleFrames++; else settleFrames = 0;
      /* A die wedged on a rim never goes still, so the roll still needs a
         hard stop. The brake normally ends it well before this. */
      var stuck = now - rollStart > 9000 / scale;
      if (settleFrames > 14 && !stuck && reseats < 6) {
        var cocked = allDice.filter(function (die) { return flatness(die) < COCKED_LIMIT; });
        if (cocked.length) {
          cocked.forEach(reseat);
          reseats++;
          settleFrames = 0;
          rollStart = now;
        }
      }
      if (settleFrames > 14 || stuck) {
        rolling = false;
        readAll();
        setReadout();
        if (navigator.vibrate) { try { navigator.vibrate([0, 10, 40, 16]); } catch (e) {} }
      }
    } else {
      /* Tilt, a turn of the screen or a die that was still moving at the
         time limit can change the faces after the read. Read again. */
      shoveFrames = shoved ? shoveFrames + 1 : 0;
      if (shoveFrames >= 3) {
        shoveFrames = 0;
        beginRoll("nudge");
      }
      if (moving) quiet = 0;
      else if (++quiet > QUIET_IDLE) {
        restGravity.x = world.gravity.x;
        restGravity.z = world.gravity.z;
      }
    }

    renderer.render(scene, camera);
    sampleFps(now);
  }

  /* ================================ input ============================ */

  var hint = document.getElementById("hint");
  var hintGone = false;
  function hideHint() {
    if (hintGone) return;
    hintGone = true;
    hint.classList.add("gone");
  }

  var down = null;
  var stir = null;

  canvas.addEventListener("pointerdown", function (e) {
    resumeAudio();
    down = { x: e.clientX, y: e.clientY, t: performance.now() };
    stir = { x: e.clientX, y: e.clientY, t: performance.now(), energy: 0, threw: false };
  });

  /* Stirring stands in for shaking on any device that withholds the
     accelerometer: the finger drags the dice around the tray, and enough
     swirling launches them, the way a hard shake does. */
  canvas.addEventListener("pointermove", function (e) {
    if (!down || !stir || !allDice.length) return;
    var now = performance.now();
    var dt = Math.max(8, now - stir.t);
    var dx = e.clientX - stir.x, dy = e.clientY - stir.y;
    stir.x = e.clientX; stir.y = e.clientY; stir.t = now;

    var pxPerMs = Math.hypot(dx, dy) / dt;
    if (pxPerMs < 0.05) return;

    /* screen pixels to tray units */
    var k = (halfW * 2) / Math.max(1, window.innerWidth);
    var wx = (dx / dt) * k * 55;
    var wz = (dy / dt) * k * 55;

    allDice.forEach(function (d) {
      d.body.velocity.x += wx * (0.5 + rnd() * 0.7);
      d.body.velocity.z += wz * (0.5 + rnd() * 0.7);
      d.body.velocity.y += rnd() * 1.6;
      d.body.angularVelocity.x += sym() * pxPerMs * 5;
      d.body.angularVelocity.y += sym() * pxPerMs * 5;
      d.body.angularVelocity.z += sym() * pxPerMs * 5;
      d.body.wakeUp();
    });

    if (!rolling) beginRoll("nudge");

    stir.energy = stir.energy * 0.93 + pxPerMs * 2.2;
    if (!stir.threw && stir.energy > settings.sens && now - lastShakeRoll > 600) {
      stir.threw = true;
      lastShakeRoll = now;
      throwDice(0, 0, Math.min(2.3, 0.9 + stir.energy / 34));
    }
  });

  canvas.addEventListener("pointerup", function (e) {
    if (!down) return;
    var threw = stir && stir.threw;
    var dx = e.clientX - down.x, dy = e.clientY - down.y;
    var dist = Math.hypot(dx, dy);
    var ms = Math.max(50, performance.now() - down.t);
    down = null;
    stir = null;
    if (threw) return;
    if (dist < 12) {
      throwDice(0, 0, 1);
    } else {
      var speed = Math.min(2.2, dist / ms * 3.2);
      throwDice(dx / dist, dy / dist, 0.8 + speed);
    }
  });

  canvas.addEventListener("pointercancel", function () { down = null; stir = null; });

  document.getElementById("rollBtn").addEventListener("click", function () {
    throwDice(0, 0, 1);
  });

  window.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { closeSheet(); return; }
    if (e.key === " " || e.key === "Enter") {
      if (document.activeElement && document.activeElement.tagName === "BUTTON") return;
      e.preventDefault();
      throwDice(0, 0, 1);
    }
  });

  /* A turn of the phone can make the tray narrower than the spot where
     a die lies. The wall would then kick the die out hard, so move it
     inside first. Its facing does not change, so the result holds. */
  window.addEventListener("resize", function () {
    layoutTray();
    allDice.forEach(function (d) {
      var p = d.body.position, mx = halfW - d.type.r, mz = halfD - d.type.r;
      p.x = Math.max(-mx, Math.min(mx, p.x));
      p.z = Math.max(-mz, Math.min(mz, p.z));
      d.mesh.position.set(p.x, p.y, p.z);
    });
    wake();
  });

  /* The readout grows a row when a big roll wraps the chips. The motion
     prompt sits above it, so its offset follows the measured height. */
  (function () {
    var readout = document.querySelector(".readout");
    function sync() {
      document.documentElement.style.setProperty(
        "--readout-h", readout.offsetHeight + "px");
    }
    if (window.ResizeObserver) new ResizeObserver(sync).observe(readout);
    else window.addEventListener("resize", sync);
    sync();
  })();

  /* ================================ motion =========================== */

  var sensorNote = document.getElementById("sensorNote");
  var motionCta = document.getElementById("motionCta");
  var motionPrompt = document.getElementById("motionPrompt");
  var motionPromptText = document.getElementById("motionPromptText");
  var diag = document.getElementById("diag");

  var sensor = {
    dmEvents: 0, doEvents: 0,
    ax: 0, ay: 0, az: 0,
    beta: 0, gamma: 0,
    jolt: 0, peak: 0,
    grant: "not asked",
    framed: window.self !== window.top,
    listening: false,
    startedAt: performance.now(),
    policy: "unknown",
    secure: !!window.isSecureContext
  };

  /* Chrome exposes whether this frame was granted the sensor features.
     That answers "blocked by the embedder" without any guessing. */
  (function () {
    var fp = document.featurePolicy || document.permissionsPolicy;
    if (!fp || !fp.allowsFeature) return;
    var bits = [];
    ["accelerometer", "gyroscope"].forEach(function (f) {
      try { bits.push(f.slice(0, 5) + (fp.allowsFeature(f) ? " yes" : " NO")); } catch (e) {}
    });
    if (bits.length) sensor.policy = bits.join(", ");
  })();

  var prevMag = null, shakeEnergy = 0, lastShakeRoll = 0;

  /* Horizontal gravity from a tilt, in tray coordinates: world x is
     screen right, world z is screen down. */
  function setTiltGravity(hx, hz) {
    if (!settings.tilt) { world.gravity.set(0, -32, 0); return; }
    var lim = 26;
    world.gravity.set(
      Math.max(-lim, Math.min(lim, hx)),
      -32,
      Math.max(-lim, Math.min(lim, hz))
    );
  }

  function onMotion(e) {
    var g = e.accelerationIncludingGravity;
    if (!g || (g.x == null && g.y == null && g.z == null)) return;

    if (sensor.dmEvents === 0) {
      hidePrompt();
      hint.textContent = "Shake to roll, tilt to slide";
    }
    sensor.dmEvents++;
    sensor.ax = g.x || 0;
    sensor.ay = g.y || 0;
    sensor.az = g.z || 0;

    /* The reading points along whichever device axis faces the sky, so
       downhill is its negative: device x is screen right, device y is
       screen up. */
    setTiltGravity(-sensor.ax * 2.4, sensor.ay * 2.4);

    var mag = Math.hypot(sensor.ax, sensor.ay, sensor.az);
    if (prevMag != null) {
      var jolt = Math.abs(mag - prevMag);
      sensor.jolt = jolt;
      shakeEnergy = shakeEnergy * 0.86 + jolt;
      sensor.peak = Math.max(sensor.peak, shakeEnergy);

      var now = performance.now();
      if (shakeEnergy > settings.sens && now - lastShakeRoll > 600) {
        lastShakeRoll = now;
        var e2 = shakeEnergy;
        shakeEnergy = 0;
        throwDice(0, 0, Math.min(2.3, 0.9 + e2 / 34));
      } else if (jolt > 0.6) {
        /* Small knocks rattle the dice without a full throw. A cube sits
           on a flat face and has to tip over an edge before it goes
           anywhere, so the kick needs a floor: scaling purely with the
           jolt moved the round dice and left the d6 sitting there. */
        var kick = 0.7 + jolt * 0.9;
        allDice.forEach(function (d) {
          d.body.velocity.x += sym() * kick;
          d.body.velocity.z += sym() * kick;
          d.body.velocity.y += rnd() * kick * 0.3;
          d.body.angularVelocity.x += sym() * kick * 1.7;
          d.body.angularVelocity.y += sym() * kick * 1.7;
          d.body.angularVelocity.z += sym() * kick * 1.7;
          d.body.wakeUp();
        });
        if (!rolling) beginRoll("nudge");
      }
    }
    prevMag = mag;
  }

  /* Fallback tilt. Some browsers deliver orientation angles while
     withholding raw acceleration, which still gives us a downhill. */
  function onOrient(e) {
    if (e.beta == null && e.gamma == null) return;
    sensor.doEvents++;
    sensor.beta = e.beta || 0;
    sensor.gamma = e.gamma || 0;
    if (sensor.dmEvents > 0) return;
    var k = 24;
    setTiltGravity(
      Math.sin(sensor.gamma * Math.PI / 180) * k,
      Math.sin(sensor.beta * Math.PI / 180) * k
    );
  }

  /* The prompt is the only thing standing between the user and the
     feature they came for, so it lives on the felt until motion is
     actually delivering events, not merely permitted. */
  function showPrompt(label) {
    if (!settings.prompt) return;
    motionPromptText.textContent = label;
    motionPrompt.hidden = false;
    hideHint();   /* one message on the felt at a time */
  }
  function hidePrompt() {
    motionPrompt.hidden = true;
  }

  /* Dismissing is remembered. Motion can still be granted later from the
     settings sheet, so this hides the prompt without closing the door. */
  document.getElementById("motionPromptDismiss").addEventListener("click", function () {
    settings.prompt = false;
    save();
    hidePrompt();
    syncPrompt();
    hint.textContent = "Stir the felt with a finger, or tap to roll";
  });
  function motionLive() {
    return sensor.dmEvents > 0;
  }

  function requestMotion(onDone) {
    resumeAudio();
    var DM = window.DeviceMotionEvent;
    var DO = window.DeviceOrientationEvent;
    if (!DM) { onDone("unsupported"); return; }
    if (typeof DM.requestPermission !== "function") {
      listen();
      onDone("not required");
      return;
    }
    var asks = [DM.requestPermission()];
    if (DO && typeof DO.requestPermission === "function") asks.push(DO.requestPermission());
    Promise.all(asks).then(function (states) {
      sensor.grant = states.join(" + ");
      if (states[0] === "granted") { listen(); sensor.startedAt = performance.now(); }
      onDone(states[0]);
    })["catch"](function (err) {
      sensor.grant = "error: " + (err && err.name ? err.name : "unknown");
      onDone("error");
    });
  }

  document.getElementById("motionPromptMain").addEventListener("click", function () {
    showPrompt("Asking\u2026");
    requestMotion(function (state) {
      if (state === "denied") {
        motionPrompt.classList.add("settled");
        showPrompt("Motion refused \u2014 stir instead");
        sensorNote.textContent = "Motion refused. Stir the felt with a finger, or press Roll.";
        setTimeout(hidePrompt, 5000);
        return;
      }
      if (state === "unsupported" || state === "error") {
        motionPrompt.classList.add("settled");
        showPrompt("No sensor \u2014 stir instead");
        setTimeout(hidePrompt, 5000);
        return;
      }
      /* Granted is not the same as delivered. Wait for a real event. */
      showPrompt("Waiting for the sensor\u2026");
      setTimeout(function () {
        if (motionLive()) {
          hidePrompt();
          hint.textContent = "Shake to roll, tilt to slide";
          return;
        }
        motionPrompt.classList.add("settled");
        showPrompt("Motion blocked \u2014 stir instead");
        setTimeout(hidePrompt, 5000);
      }, 2200);
    });
  });

  function listen() {
    if (sensor.listening) return;
    sensor.listening = true;
    window.addEventListener("devicemotion", onMotion);
    window.addEventListener("deviceorientation", onOrient);
  }

  function startMotion() {
    var DM = window.DeviceMotionEvent;
    if (!DM) {
      sensor.grant = "no DeviceMotionEvent";
      sensorNote.textContent = "This browser reports no motion sensor. Stir the felt with a finger to rattle the dice, or press Roll.";
      return;
    }
    if (typeof DM.requestPermission === "function") {
      sensor.grant = "waiting for tap";
      motionCta.classList.add("show");
      showPrompt("Enable shake & tilt");
      sensorNote.textContent = "This browser asks before a page may read motion. Tap the button on the tray to grant it.";
      return;
    }
    sensor.grant = "not required";
    listen();
    sensorNote.textContent = "Listening for the motion sensor. Shake to throw, tilt to roll the dice to one side. Stirring the felt works either way.";
  }

  motionCta.addEventListener("click", function () {
    resumeAudio();
    var DM = window.DeviceMotionEvent;
    var DO = window.DeviceOrientationEvent;
    var asks = [DM.requestPermission()];
    if (DO && typeof DO.requestPermission === "function") asks.push(DO.requestPermission());

    Promise.all(asks).then(function (states) {
      sensor.grant = states.join(" + ");
      if (states[0] === "granted") {
        listen();
        motionCta.classList.remove("show");
        sensorNote.textContent = "Motion allowed. Shake to throw, tilt to roll the dice to one side.";
        sensor.startedAt = performance.now();
      } else {
        sensorNote.textContent = "Motion refused. Tap the felt or press Roll to throw.";
      }
    })["catch"](function (err) {
      sensor.grant = "error: " + (err && err.name ? err.name : "unknown");
      sensorNote.textContent = "The motion request failed, which usually means the page is embedded. Tap the felt or press Roll to throw.";
    });
  });

  /* Live sensor readout, so a dead sensor is visible rather than guessed. */
  function updateDiag() {
    var age = (performance.now() - sensor.startedAt) / 1000;
    var verdict;
    if (sensor.dmEvents > 0) {
      verdict = '<b class="good">accelerometer live</b>';
    } else if (sensor.doEvents > 0) {
      verdict = '<b class="good">orientation live</b>, acceleration withheld: tilt works, shake does not';
    } else if (!sensor.listening) {
      verdict = '<b>not listening yet</b>';
    } else if (age > 3) {
      verdict = '<b class="bad">no sensor events</b>' +
        (sensor.framed ? " — the page is embedded in a frame that is not passing the sensor through" : "");
    } else {
      verdict = "<b>waiting…</b>";
    }

    diag.innerHTML =
      verdict + "\n" +
      "motion " + sensor.dmEvents + " ev   orient " + sensor.doEvents + " ev   " +
      "permission " + sensor.grant + "\n" +
      (sensor.framed ? "in a frame" : "top level") + "   secure " + (sensor.secure ? "yes" : "NO") +
      "   policy " + sensor.policy + "\n" +
      "accel  x " + sensor.ax.toFixed(1) + "  y " + sensor.ay.toFixed(1) + "  z " + sensor.az.toFixed(1) +
      "   tilt β " + sensor.beta.toFixed(0) + "  γ " + sensor.gamma.toFixed(0) + "\n" +
      "shake now " + shakeEnergy.toFixed(1) + "   peak " + sensor.peak.toFixed(1) +
      "   throws at " + settings.sens;
  }
  setInterval(function () {
    if (sheet.classList.contains("open")) updateDiag();
  }, 220);

  /* ============================ settings sheet ======================= */

  var sheet = document.getElementById("sheet");
  var scrim = document.getElementById("scrim");
  var pool = document.getElementById("pool");
  var poolCount = document.getElementById("poolCount");

  function openSheet() { sheet.classList.add("open"); scrim.classList.add("open"); }
  function closeSheet() { sheet.classList.remove("open"); scrim.classList.remove("open"); }

  document.getElementById("cog").addEventListener("click", openSheet);
  document.getElementById("closeSheet").addEventListener("click", closeSheet);
  scrim.addEventListener("click", closeSheet);

  /* Flat silhouette for the sheet rows, so the list stays cheap. */
  var SIL = { d4: 3, d6: 4, d8: 4, d10: 5, d12: 5, d20: 6, d100: 5 };
  function drawSilhouette(cv, type) {
    var c = cv.getContext("2d");
    var s = cv.width;
    c.clearRect(0, 0, s, s);
    c.translate(s / 2, s / 2);
    var n = SIL[type.id], r = s * 0.34;
    var rot = type.id === "d6" ? Math.PI / 4 : -Math.PI / 2;
    c.beginPath();
    for (var i = 0; i < n; i++) {
      var a = rot + i * Math.PI * 2 / n;
      var x = Math.cos(a) * r, y = Math.sin(a) * r;
      if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
    }
    c.closePath();
    c.lineJoin = "round";
    c.lineWidth = s * 0.09;
    c.fillStyle = type.body;
    c.strokeStyle = type.body;
    c.fill();
    c.stroke();
    c.fillStyle = type.ink;
    c.font = "700 " + (s * 0.26).toFixed(0) + "px Cinzel, Georgia, serif";
    c.textAlign = "center";
    c.textBaseline = "middle";
    c.fillText(type.percentile ? "%" : String(type.faces), 0, s * 0.01);
  }

  function buildSheet() {
    TYPES.forEach(function (t) {
      var row = document.createElement("div");
      row.className = "row";

      var pv = document.createElement("canvas");
      pv.width = pv.height = 84;
      pv.setAttribute("aria-hidden", "true");
      drawSilhouette(pv, t);
      row.appendChild(pv);

      var name = document.createElement("div");
      name.className = "name";
      name.innerHTML = t.id + '<span class="range">' + t.range + "</span>";
      row.appendChild(name);

      var step = document.createElement("div");
      step.className = "stepper";
      var minus = document.createElement("button");
      minus.type = "button";
      minus.textContent = "−";
      minus.setAttribute("aria-label", "One fewer " + t.id);
      var n = document.createElement("span");
      n.className = "n";
      var plus = document.createElement("button");
      plus.type = "button";
      plus.textContent = "+";
      plus.setAttribute("aria-label", "One more " + t.id);
      minus.addEventListener("click", function () { bump(t.id, -1); });
      plus.addEventListener("click", function () { bump(t.id, 1); });
      step.appendChild(minus);
      step.appendChild(n);
      step.appendChild(plus);
      row.appendChild(step);

      pool.appendChild(row);
      t._ui = { row: row, n: n, minus: minus, plus: plus, canvas: pv };
    });
    syncSheet();
  }

  function bump(id, delta) {
    var cur = settings.counts[id] || 0;
    var next = cur + delta;
    if (next < 0) return;
    if (delta > 0 && poolSize() >= MAX_DICE) return;
    if (next === 0) delete settings.counts[id];
    else settings.counts[id] = next;
    save();
    buildPool();
    syncSheet();
  }

  function syncSheet() {
    var total = poolSize();
    TYPES.forEach(function (t) {
      var c = settings.counts[t.id] || 0;
      t._ui.n.textContent = c;
      t._ui.n.className = c ? "n" : "n zero";
      t._ui.row.className = c ? "row active" : "row";
      t._ui.minus.disabled = c === 0;
      t._ui.plus.disabled = total >= MAX_DICE;
    });
    poolCount.textContent = total + " / " + MAX_DICE + " dice";
  }

  var sens = document.getElementById("sens");
  sens.value = settings.sens;
  sens.addEventListener("input", function () {
    settings.sens = parseInt(sens.value, 10);
    save();
  });

  var speedSeg = document.getElementById("speed");
  var speedBtns = speedSeg.querySelectorAll("button");
  function syncSpeed() {
    for (var i = 0; i < speedBtns.length; i++) {
      speedBtns[i].setAttribute("aria-checked",
        speedBtns[i].dataset.speed === settings.speed ? "true" : "false");
    }
  }
  syncSpeed();
  speedSeg.addEventListener("click", function (e) {
    var btn = e.target.closest("button[data-speed]");
    if (!btn) return;
    settings.speed = btn.dataset.speed;
    syncSpeed();
    save();
  });

  var promptSw = document.getElementById("promptSw");
  function syncPrompt() {
    promptSw.setAttribute("aria-checked", settings.prompt ? "true" : "false");
  }
  syncPrompt();
  promptSw.addEventListener("click", function () {
    settings.prompt = !settings.prompt;
    save();
    syncPrompt();
    if (settings.prompt) startMotion(); else hidePrompt();
  });

  var tiltBtn = document.getElementById("tilt");
  tiltBtn.setAttribute("aria-checked", settings.tilt ? "true" : "false");
  tiltBtn.addEventListener("click", function () {
    settings.tilt = !settings.tilt;
    tiltBtn.setAttribute("aria-checked", settings.tilt ? "true" : "false");
    if (!settings.tilt) world.gravity.set(0, -32, 0);
    save();
  });

  var sfxBtn = document.getElementById("sfx");
  var soundBtn = document.getElementById("soundBtn");
  function syncSfx() {
    sfxBtn.setAttribute("aria-checked", settings.sfx ? "true" : "false");
    soundBtn.setAttribute("aria-pressed", settings.sfx ? "true" : "false");
    soundBtn.classList.toggle("off", !settings.sfx);
    soundBtn.setAttribute("aria-label", settings.sfx ? "Mute dice sounds" : "Unmute dice sounds");
    /* SVG display attributes, not inline styles: the CSP forbids those. */
    document.getElementById("wave1").setAttribute("display", settings.sfx ? "inline" : "none");
    document.getElementById("wave2").setAttribute("display", settings.sfx ? "inline" : "none");
    document.getElementById("muteX").setAttribute("display", settings.sfx ? "none" : "inline");
  }
  function toggleSfx() {
    settings.sfx = !settings.sfx;
    if (settings.sfx) resumeAudio();
    syncSfx();
    save();
  }
  sfxBtn.addEventListener("click", toggleSfx);
  soundBtn.addEventListener("click", toggleSfx);

  /* ================================= boot ============================ */

  layoutTray();
  buildSheet();
  syncSfx();
  buildPool();
  applyQuality();
  startMotion();
  requestAnimationFrame(tick);

  /* If the sensor never speaks, say so on the felt rather than leaving
     the shake instruction sitting there doing nothing. */
  setTimeout(function () {
    if (sensor.dmEvents || sensor.doEvents || !sensor.listening) return;
    showPrompt("Enable shake & tilt");
    hint.textContent = "Stir the felt with a finger, or tap to roll";
    sensorNote.textContent =
      "No sensor events arrived, so this page is not being given the accelerometer. " +
      "Stir the felt with a finger instead: it rattles the dice and, kept up, throws them.";
  }, 3500);

  /* Cinzel arrives after the first paint, so redraw the face atlases. */
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function () {
      Object.keys(kits).forEach(function (id) {
        var type = TYPE_BY_ID[id];
        var kit = kits[id];
        var atlas = buildAtlas(type, faceLabels(type, kit, kit.ready), kit.spec);
        kit.material.map.dispose();
        kit.material.map = atlas.texture;
        kit.material.needsUpdate = true;
      });
      wake();
      TYPES.forEach(function (t) { if (t._ui) drawSilhouette(t._ui.canvas, t); });
    });
  }

  setTimeout(hideHint, 10000);
})();
