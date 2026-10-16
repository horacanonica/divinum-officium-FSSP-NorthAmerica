const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function monthsInWindow(start, end) {
  const [sy, sm] = start.split("-").map(Number);
  const [ey, em] = end.split("-").map(Number);
  const out = [];
  let year = sy;
  let month = sm;
  while (year < ey || (year === ey && month <= em)) {
    out.push({ year: year, month: month });
    month += 1;
    if (month === 13) {
      month = 1;
      year += 1;
    }
  }
  return out;
}

function groupByYear(items) {
  const groups = [];
  items.forEach(function (item) {
    let group = groups.find(function (entry) { return entry.year === item.year; });
    if (!group) {
      group = { year: item.year, months: [] };
      groups.push(group);
    }
    group.months.push(item.month);
  });
  return groups;
}

function fileVariant(file) {
  return file.variant || "la-en";
}

function fileIndex(calendar, variant) {
  const index = {};
  (calendar.files || []).forEach(function (file) {
    if (fileVariant(file) !== variant) return;
    if (file.type === "year") index["y" + file.year] = file;
    if (file.type === "month") index["m" + file.year + "-" + file.month] = file;
  });
  return index;
}

function downloadUrl(catalog, name) {
  return "https://github.com/" + catalog.repo + "/releases/download/" + catalog.release + "/" + encodeURIComponent(name);
}

function sizeLabel(bytes) {
  if (!bytes) return "";
  if (bytes < 1000000) return Math.max(1, Math.round(bytes / 1000)) + " KB";
  return (bytes / 1000000).toFixed(1) + " MB";
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function linkOrPending(catalog, file, className, label) {
  if (!file) {
    const pending = el("span", className + " pending", label);
    pending.title = "Not generated yet";
    return pending;
  }
  const link = el("a", className, label);
  link.href = downloadUrl(catalog, file.name);
  const size = sizeLabel(file.bytes);
  link.title = size ? label + ", " + size : label;
  return link;
}

function filterText(calendar) {
  return [calendar.name, calendar.place, calendar.region, calendar.version].join(" ").toLowerCase();
}

function render(catalog) {
  const variant = document.body.dataset.variant || "la";
  const listing = document.getElementById("listing");
  const contents = document.getElementById("contents");
  const status = document.getElementById("status");
  listing.textContent = "";
  contents.textContent = "";
  const windowMonths = monthsInWindow(catalog.window.start, catalog.window.end);
  const byRegion = new Map();
  (catalog.region_order || []).forEach(function (region) { byRegion.set(region, []); });
  (catalog.calendars || []).forEach(function (calendar) {
    const region = calendar.region || "Other";
    if (!byRegion.has(region)) byRegion.set(region, []);
    byRegion.get(region).push(calendar);
  });

  const heading = el("h2", null, "Calendars");
  contents.appendChild(heading);
  let any = false;

  byRegion.forEach(function (calendars, region) {
    if (!calendars.length) return;
    any = true;
    const section = el("section", "region");
    section.id = "region-" + region.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    section.appendChild(el("h2", null, region));

    const tocRegion = el("div", "toc-region");
    tocRegion.appendChild(el("h3", null, region));
    const list = el("ul");

    calendars.forEach(function (calendar) {
      const anchorId = "loc-" + calendar.slug;
      const text = filterText(calendar);
      const item = el("li");
      const tocLink = el("a", null, calendar.name);
      tocLink.href = "#" + anchorId;
      item.dataset.filter = text;
      item.appendChild(tocLink);
      list.appendChild(item);

      const card = el("section", "card");
      card.id = anchorId;
      card.dataset.filter = text;
      card.appendChild(el("h3", null, calendar.name));
      if (calendar.place) card.appendChild(el("p", "place", calendar.place));
      const files = fileIndex(calendar, variant);
      groupByYear(windowMonths).forEach(function (group) {
        const block = el("div", "year-block");
        block.appendChild(el("span", "year-label", String(group.year)));
        group.months.forEach(function (month) {
          const file = files["m" + group.year + "-" + month];
          block.appendChild(linkOrPending(catalog, file, "chip", MONTHS[month - 1]));
        });
        block.appendChild(linkOrPending(catalog, files["y" + group.year], "year-link", "Full year"));
        card.appendChild(block);
      });
      const back = el("p", "top-link");
      const backLink = el("a", null, "Back to top");
      backLink.href = "#top";
      back.appendChild(backLink);
      card.appendChild(back);
      section.appendChild(card);
    });

    tocRegion.appendChild(list);
    contents.appendChild(tocRegion);
    listing.appendChild(section);
  });

  if (!any) contents.textContent = "";

  const count = (catalog.calendars || []).length;
  status.textContent = count
    ? count + " calendars, " + catalog.window.start + " through " + catalog.window.end + "."
    : "No calendars are listed yet.";
  const updated = document.getElementById("updated");
  if (catalog.updated) {
    updated.textContent = "Catalog updated " + catalog.updated.replace("T", " ").replace("Z", " UTC") + ".";
  }
}

function applyFilter() {
  const query = document.getElementById("filter").value.trim().toLowerCase();
  document.querySelectorAll(".card").forEach(function (card) {
    const show = !query || card.dataset.filter.indexOf(query) !== -1;
    card.classList.toggle("hidden", !show);
  });
  document.querySelectorAll(".region").forEach(function (region) {
    const visible = region.querySelector(".card:not(.hidden)");
    region.classList.toggle("hidden", !visible);
  });
  document.querySelectorAll(".toc-region li").forEach(function (item) {
    const show = !query || item.dataset.filter.indexOf(query) !== -1;
    item.classList.toggle("hidden", !show);
  });
  document.querySelectorAll(".toc-region").forEach(function (region) {
    const visible = region.querySelector("li:not(.hidden)");
    region.classList.toggle("hidden", !visible);
  });
  const status = document.getElementById("status");
  if (!status.dataset.base) status.dataset.base = status.textContent;
  const visibleCards = document.querySelectorAll(".card:not(.hidden)").length;
  if (query && !visibleCards) {
    status.textContent = "No calendars match.";
  } else {
    status.textContent = status.dataset.base || status.textContent;
  }
}

document.getElementById("filter").addEventListener("input", applyFilter);

fetch("catalog.json", { cache: "no-cache" })
  .then(function (response) {
    if (!response.ok) throw new Error("Catalog request failed");
    return response.json();
  })
  .then(render)
  .catch(function () {
    const status = document.getElementById("status");
    status.className = "error";
    status.textContent = "The catalog could not be loaded. Try again in a moment.";
  });
