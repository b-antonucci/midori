import { main } from "/static/ui/javascript/ui/ui.mjs";

document.getElementById("no-context-menu-wrapper").addEventListener("contextmenu", function(e) {e.preventDefault();});

document.addEventListener("DOMContentLoaded", () => {
  main();
});
