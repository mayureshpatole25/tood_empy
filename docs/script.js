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

  // The default hero background for every visitor, set as early as
  // possible (before anything else runs) so there's no visible swap once
  // the page has painted.
  var DEFAULT_WALLPAPER = "assets/wallpapers/frog.jpg";
  var sceneBg = document.querySelector(".scene-bg");
  if (sceneBg) {
    sceneBg.style.backgroundImage = "url(\"" + DEFAULT_WALLPAPER + "\")";
  }

  // Real interactivity, matching the actual app: click a box to strike
  // a line through it, click text to edit it, press Enter at the end of
  // a line to open a new blank one right below (focused and ready to
  // type), press Backspace on an empty line to remove it.
  var DOWNLOAD_URL = "/api/download";

  function addRow(container, itemText, done, afterEl) {
    var row = document.createElement("div");
    row.className = "sticky-row" + (done ? " done" : "");
    var box = document.createElement("span");
    box.className = "sticky-box";
    box.addEventListener("click", function (e) {
      e.stopPropagation();
      row.classList.toggle("done");
      if (row.classList.contains("done") && text.textContent.trim().toLowerCase() === "download tood") {
        var a = document.createElement("a");
        a.href = DOWNLOAD_URL;
        a.download = "";
        document.body.appendChild(a);
        a.click();
        a.remove();
      }
    });
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
        var newRow = addRow(container, "", false, row);
        newRow.querySelector(".sticky-text").focus();
      } else if (e.key === "Backspace" && text.textContent === "" && container.children.length > 1) {
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
    if (afterEl && afterEl.nextSibling) container.insertBefore(row, afterEl.nextSibling);
    else container.appendChild(row);
    return row;
  }

  ITEMS.forEach(function (item) { addRow(rows, item.t, item.done, null); });

  function addAddItemButton(card, container) {
    var btn = document.createElement("button");
    btn.className = "sticky-add-item";
    btn.type = "button";
    btn.innerHTML = '<span class="plus-glyph">+</span> Add item';
    btn.addEventListener("pointerdown", function (e) { e.stopPropagation(); });
    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      var newRow = addRow(container, "", false, container.lastElementChild);
      newRow.querySelector(".sticky-text").focus();
    });
    card.appendChild(btn);
  }
  addAddItemButton(document.getElementById("sticky"), rows);

  (function () {
    var existingTitle = document.querySelector("#sticky .sticky-title");
    existingTitle.addEventListener("pointerdown", function (e) { e.stopPropagation(); });
    existingTitle.addEventListener("mousedown", function (e) { e.stopPropagation(); });
    existingTitle.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); existingTitle.blur(); }
    });
  })();

  // ---------- color picker, "+ Add item", new-sticky, close ----------
  // Hex values come straight from the real macOS app's source
  // (StickyColor.swift) so the web demo matches what you actually get.
  var FREE_COLORS = ["#FE9591", "#F8E6CF", "#72D6E9", "#FE6926", "#17C862"];
  var CYCLE_COLORS = ["#72D6E9", "#17C862", "#FE9591", "#FE6926", "#F8E6CF"]; // blue, green, pink, orange, cream
  var cycleIndex = 0;
  var newStickyCount = 0;

  function nextZIndex() {
    var maxZ = 8;
    document.querySelectorAll(".card-shared").forEach(function (s) {
      maxZ = Math.max(maxZ, parseInt(s.style.zIndex || 8, 10));
    });
    return maxZ + 1;
  }

  function closeAllPopovers() {
    document.querySelectorAll(".card-shared.popover-open").forEach(function (c) {
      c.classList.remove("popover-open");
    });
  }
  document.addEventListener("pointerdown", function (e) {
    if (!e.target.closest(".sticky-toolbar")) closeAllPopovers();
  });

  function applyColor(card, hex) {
    card.style.background = hex;
    card.querySelectorAll(".color-swatch").forEach(function (sw) {
      sw.classList.toggle("active", sw.dataset.hex.toLowerCase() === hex.toLowerCase());
    });
  }

  function makeSwatch(hex) {
    var b = document.createElement("button");
    b.className = "color-swatch";
    b.type = "button";
    b.style.background = hex;
    b.dataset.hex = hex;
    b.setAttribute("aria-label", "Set color " + hex);
    return b;
  }

  // Injects the close button, hover toolbar (color picker + new sticky)
  // onto any card — the two on-page stickies at load, and every one
  // created afterward via the "+" button.
  function wireCardInteractive(card) {
    var close = document.createElement("button");
    close.className = "sticky-close";
    close.type = "button";
    close.setAttribute("aria-label", "Close");
    close.innerHTML = "&times;";
    close.addEventListener("click", function (e) {
      e.stopPropagation();
      card.remove();
      updateSceneHeight();
    });
    card.appendChild(close);

    var toolbar = document.createElement("div");
    toolbar.className = "sticky-toolbar";

    var paletteBtn = document.createElement("button");
    paletteBtn.className = "toolbar-btn";
    paletteBtn.type = "button";
    paletteBtn.setAttribute("aria-label", "Change color");
    paletteBtn.innerHTML = '<span class="toolbar-dots"><span></span><span></span><span></span><span></span></span>';
    paletteBtn.addEventListener("click", function (e) {
      e.stopPropagation();
      var isOpen = card.classList.contains("popover-open");
      closeAllPopovers();
      card.classList.toggle("popover-open", !isOpen);
    });

    var addBtn = document.createElement("button");
    addBtn.className = "toolbar-btn";
    addBtn.type = "button";
    addBtn.setAttribute("aria-label", "New sticky");
    addBtn.textContent = "+";
    addBtn.addEventListener("click", function (e) {
      e.stopPropagation();
      createSticky();
    });

    var popover = document.createElement("div");
    popover.className = "color-popover";

    var freeRow = document.createElement("div");
    freeRow.className = "color-popover-row";
    FREE_COLORS.forEach(function (hex) {
      var sw = makeSwatch(hex);
      sw.addEventListener("click", function (e) {
        e.stopPropagation();
        applyColor(card, hex);
        card.classList.remove("popover-open");
      });
      freeRow.appendChild(sw);
    });

    popover.appendChild(freeRow);
    toolbar.appendChild(paletteBtn);
    toolbar.appendChild(addBtn);
    toolbar.appendChild(popover);
    card.appendChild(toolbar);

    // Mark the swatch matching this card's current paper as active, if any.
    var currentHex = (card.style.background || "").trim();
    if (currentHex) {
      card.querySelectorAll(".color-swatch").forEach(function (sw) {
        sw.classList.toggle("active", sw.dataset.hex.toLowerCase() === currentHex.toLowerCase());
      });
    }
  }

  function createSticky() {
    newStickyCount++;
    var hex = CYCLE_COLORS[cycleIndex % CYCLE_COLORS.length];
    cycleIndex++;

    var card = document.createElement("div");
    card.className = "sticky card-shared";
    card.style.background = hex;

    var head = document.createElement("div");
    head.className = "sticky-head";
    var title = document.createElement("div");
    title.className = "sticky-title";
    title.contentEditable = "true";
    title.spellcheck = false;
    title.textContent = "To Do";
    title.addEventListener("pointerdown", function (e) { e.stopPropagation(); });
    title.addEventListener("mousedown", function (e) { e.stopPropagation(); });
    title.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); title.blur(); }
    });
    var date = document.createElement("div");
    date.className = "sticky-date";
    date.textContent = document.getElementById("sdate").textContent;
    head.appendChild(title);
    head.appendChild(date);

    var rowsContainer = document.createElement("div");
    rowsContainer.className = "sticky-rows";

    card.appendChild(head);
    card.appendChild(rowsContainer);
    document.getElementById("cardsRow").appendChild(card);

    var newRow = addRow(rowsContainer, "", false, null);
    addAddItemButton(card, rowsContainer);

    var offset = 26 * (newStickyCount % 6);
    card.style.zIndex = nextZIndex();
    makeDraggable(card, 34 + offset, 40 + offset);
    wireCardInteractive(card);
    applyColor(card, hex);
    updateSceneHeight();

    newRow.querySelector(".sticky-text").focus();
  }

  wireCardInteractive(document.getElementById("headlineCard"));
  wireCardInteractive(document.getElementById("sticky"));

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
      if (e.target.closest(".sticky-text, .sticky-box, .sticky-title, .sticky-toolbar, .color-popover, .sticky-close, .sticky-add-item")) return;
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

(function () {
  "use strict";
  var CANDY_CHECKOUT_URL = "https://buy.polar.sh/polar_cl_sK0AiofXosBUkvEPktaB0wxzgjsrPHHPRghJi3ZyImq";
  var overlay = document.getElementById("whatsnewOverlay");
  if (!overlay) return;

  function dismiss() { overlay.classList.remove("show"); }

  setTimeout(function () { overlay.classList.add("show"); }, 1000);

  document.getElementById("whatsnewText").addEventListener("click", function () {
    window.open(CANDY_CHECKOUT_URL, "_blank", "noopener");
  });
  document.getElementById("whatsnewClose").addEventListener("click", function (e) {
    e.stopPropagation();
    dismiss();
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && overlay.classList.contains("show")) dismiss();
  });
})();
