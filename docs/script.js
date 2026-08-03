(function () {
  "use strict";

  var ITEMS = [
    { t: "Download Tood", done: false },
    { t: "Water plants", done: false },
    { t: "Reply to emails", done: false },
    { t: "Prep for meeting", done: true }
  ];

  var scene = document.getElementById("scene");
  var rows = document.getElementById("stickyRows");

  // A different wallpaper per visit: pick one at random on every load,
  // set as early as possible (before anything else runs) so there's no
  // visible swap once the page has painted.
  var WALLPAPERS = [
    "assets/wallpaper.jpg",
    "assets/wallpapers/macOS3.jpg",
    "assets/wallpapers/macOS4.jpg",
    "assets/wallpapers/macOS5.jpg",
    "assets/wallpapers/macOS14.jpg",
    "assets/wallpapers/macOS15.jpg"
  ];
  var sceneBg = document.querySelector(".scene-bg");
  if (sceneBg) {
    var pick = WALLPAPERS[Math.floor(Math.random() * WALLPAPERS.length)];
    sceneBg.style.backgroundImage = "url(\"" + pick + "\")";
  }

  // Real interactivity, matching the actual app: click a box to strike
  // a line through it, click text to edit it, press Enter at the end of
  // a line to open a new blank one right below (focused and ready to
  // type), press Backspace on an empty line to remove it.
  function addRow(itemText, done, afterEl) {
    var row = document.createElement("div");
    row.className = "sticky-row" + (done ? " done" : "");
    var box = document.createElement("span");
    box.className = "sticky-box";
    box.addEventListener("click", function (e) { e.stopPropagation(); row.classList.toggle("done"); });
    var text = document.createElement("span");
    text.className = "sticky-text";
    text.contentEditable = "true";
    text.spellcheck = false;
    text.textContent = itemText;
    text.addEventListener("pointerdown", function (e) { e.stopPropagation(); });
    text.addEventListener("mousedown", function (e) { e.stopPropagation(); });
    text.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        e.preventDefault();
        var newRow = addRow("", false, row);
        newRow.querySelector(".sticky-text").focus();
      } else if (e.key === "Backspace" && text.textContent === "" && rows.children.length > 1) {
        e.preventDefault();
        var prev = row.previousElementSibling || row.nextElementSibling;
        row.remove();
        if (prev) {
          var t = prev.querySelector(".sticky-text");
          t.focus();
          var range = document.createRange();
          range.selectNodeContents(t);
          range.collapse(false);
          var sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(range);
        }
      }
    });
    row.appendChild(box);
    row.appendChild(text);
    if (afterEl && afterEl.nextSibling) rows.insertBefore(row, afterEl.nextSibling);
    else rows.appendChild(row);
    return row;
  }

  ITEMS.forEach(function (item) { addRow(item.t, item.done, null); });

  // Both cards start laid out side by side via flex (so sizing/gap stay
  // responsive), then get measured once and switched to absolute so
  // they're each freely draggable, same as a real desktop.
  // A real drag gesture only starts once the pointer has actually moved a
  // few pixels — without this, every plain click (toggling a checkbox,
  // clicking into text to edit it) was immediately grabbing pointer
  // capture on the whole card, which is what made clicking feel broken.
  function makeDraggable(el, initLeft, initTop) {
    var THRESHOLD = 4;
    var startX, startY, originLeft, originTop, parentOffsetX, parentOffsetY, dragging = false, pointerId = null;
    el.style.position = "absolute";
    el.style.left = initLeft + "px";
    el.style.top = initTop + "px";
    el.style.margin = "0";

    // el's containing block is .cards-row (its nearest positioned ancestor),
    // not .scene — but dragging/clamping should still feel like "anywhere
    // on screen". So all the math below works in scene-relative coordinates,
    // then converts to cards-row-relative only at the very end, right
    // before writing el.style.left/top.
    el.addEventListener("pointerdown", function (e) {
      if (e.target.classList.contains("sticky-text") || e.target.classList.contains("sticky-box")) return;
      pointerId = e.pointerId;
      dragging = false;
      var sr = scene.getBoundingClientRect();
      var pr = el.offsetParent.getBoundingClientRect();
      parentOffsetX = pr.left - sr.left;
      parentOffsetY = pr.top - sr.top;
      var er = el.getBoundingClientRect();
      originLeft = er.left - sr.left;
      originTop = er.top - sr.top;
      startX = e.clientX; startY = e.clientY;
    });
    el.addEventListener("pointermove", function (e) {
      if (pointerId === null || e.pointerId !== pointerId) return;
      var dx = e.clientX - startX, dy = e.clientY - startY;
      if (!dragging) {
        if (Math.abs(dx) < THRESHOLD && Math.abs(dy) < THRESHOLD) return;
        dragging = true;
        el.setPointerCapture(pointerId);
        el.classList.add("dragging");
        var all = document.querySelectorAll(".card-shared");
        var maxZ = 8;
        all.forEach(function (s) { maxZ = Math.max(maxZ, parseInt(s.style.zIndex || 8, 10)); });
        el.style.zIndex = maxZ + 1;
      }
      var sr = scene.getBoundingClientRect();
      var newLeft = Math.max(-60, Math.min(sr.width - 60, originLeft + dx));
      var newTop = Math.max(-40, Math.min(sr.height - 60, originTop + dy));
      el.style.left = (newLeft - parentOffsetX) + "px";
      el.style.top = (newTop - parentOffsetY) + "px";
    });
    function endDrag() {
      if (dragging) {
        el.classList.remove("dragging");
        try { el.releasePointerCapture(pointerId); } catch (err) {}
      }
      dragging = false;
      pointerId = null;
    }
    el.addEventListener("pointerup", endDrag);
    el.addEventListener("pointercancel", endDrag);
  }

  // Wait for everything (fonts, the photo) to actually finish painting
  // before measuring the flex layout — measuring too early was one risk.
  // The other, bigger one: measure BOTH cards' flex positions first, then
  // convert both to absolute — doing it one at a time meant pulling the
  // first card out of the flex flow immediately reflowed the second card
  // into its place before it got measured, so they landed stacked on top
  // of each other instead of side by side.
  function initCards() {
    var headline = document.getElementById("headlineCard");
    var sticky = document.getElementById("sticky");
    // Measure each card's offset relative to its own offsetParent (the
    // nearest positioned ancestor, i.e. .cards-row) — that's the box its
    // left/top will actually be resolved against once it becomes
    // position:absolute, so this is what keeps it from jumping.
    var hParentRect = headline.offsetParent.getBoundingClientRect();
    var sParentRect = sticky.offsetParent.getBoundingClientRect();
    var hRect = headline.getBoundingClientRect();
    var sRect = sticky.getBoundingClientRect();
    makeDraggable(headline, hRect.left - hParentRect.left, hRect.top - hParentRect.top);
    makeDraggable(sticky, sRect.left - sParentRect.left, sRect.top - sParentRect.top);
  }

  // Everything inside .scene is position:absolute, so the scene's own box
  // never naturally grows to fit its content (e.g. when the cards wrap to
  // two rows on a narrow window). Without this, .dock-wrap/.credit — both
  // pinned to the scene's bottom edge — would sit under a fixed 100vh mark
  // instead of below the real content, and the page couldn't scroll far
  // enough to reach anything below that mark.
  function updateSceneHeight() {
    var cards = document.querySelectorAll(".card-shared");
    var sceneRect = scene.getBoundingClientRect();
    var maxBottom = 0;
    cards.forEach(function (el) {
      var r = el.getBoundingClientRect();
      maxBottom = Math.max(maxBottom, r.bottom - sceneRect.top);
    });
    var dockSpace = 140; // room for the dock + credit line below the cards
    scene.style.minHeight = Math.max(window.innerHeight, maxBottom + dockSpace) + "px";
  }

  if (document.readyState === "complete") {
    requestAnimationFrame(function () { requestAnimationFrame(function () { initCards(); updateSceneHeight(); }); });
  } else {
    window.addEventListener("load", function () {
      requestAnimationFrame(function () { requestAnimationFrame(function () { initCards(); updateSceneHeight(); }); });
    });
  }

  var resizeTimer = null;
  window.addEventListener("resize", function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(updateSceneHeight, 120);
  });

  var dockItems = document.querySelectorAll(".dock-item");
  function toggleSibling(items, index, offset, cls, add) {
    var sib = items[index + offset];
    if (sib) sib.classList.toggle(cls, add);
  }
  dockItems.forEach(function (item, index) {
    item.addEventListener("mouseenter", function () {
      item.classList.add("hover");
      toggleSibling(dockItems, index, -1, "sibling-close", true);
      toggleSibling(dockItems, index, 1, "sibling-close", true);
      toggleSibling(dockItems, index, -2, "sibling-far", true);
      toggleSibling(dockItems, index, 2, "sibling-far", true);
    });
    item.addEventListener("mouseleave", function () {
      item.classList.remove("hover");
      toggleSibling(dockItems, index, -1, "sibling-close", false);
      toggleSibling(dockItems, index, 1, "sibling-close", false);
      toggleSibling(dockItems, index, -2, "sibling-far", false);
      toggleSibling(dockItems, index, 2, "sibling-far", false);
    });
  });

  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  var now = new Date();
  var h = now.getHours();
  var ampm = h >= 12 ? "PM" : "AM";
  var h12 = h % 12 || 12;
  var m = now.getMinutes() < 10 ? "0" + now.getMinutes() : now.getMinutes();
  document.getElementById("clock").textContent = days[now.getDay()] + " " + h12 + ":" + m + " " + ampm;
  document.getElementById("sdate").textContent = months[now.getMonth()] + " " + now.getDate() + ", " + now.getFullYear();
})();
