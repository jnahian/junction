// Anything pointing off-site opens in a new tab. rel=noopener stops the new page from
// reaching back through window.opener; noreferrer keeps our URL out of its referrer.
for (const a of document.querySelectorAll("a[href]")) {
  if (a.hostname && a.hostname !== location.hostname) {
    a.target = "_blank";
    a.rel = "noopener noreferrer";
  }
}
