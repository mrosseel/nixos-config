/* The app is a module, and a module that fails to load or parse runs
   nothing. This classic script shows the fatal note in that case. */
window.addEventListener("load", function () {
  if (!window.diceTrayReady) document.getElementById("fatal").classList.add("show");
});
