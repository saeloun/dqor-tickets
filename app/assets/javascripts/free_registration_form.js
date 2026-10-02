(() => {
  const dialog = document.querySelector("[data-registration-dialog]");
  const opener = document.querySelector("[data-open-registration]");
  if (!dialog || !opener || typeof dialog.showModal !== "function") return;
  const form = dialog.querySelector("form");
  const show = () => { if (!dialog.open) dialog.showModal(); };
  const hide = () => { if (dialog.open) dialog.close(); opener.focus(); };
  dialog.removeAttribute("open");
  history.replaceState({ registration: "event" }, "");
  history.pushState({ registration: "questions" }, "");
  show();
  opener.addEventListener("click", () => { history.pushState({ registration: "questions" }, ""); show(); });
  dialog.querySelector("[data-close-registration]").addEventListener("click", (event) => { event.preventDefault(); history.back(); });
  dialog.addEventListener("cancel", (event) => { event.preventDefault(); history.back(); });
  window.addEventListener("popstate", (event) => { event.state?.registration === "questions" ? show() : hide(); });
  form.addEventListener("input", (event) => {
    const field = event.target.closest(".question-field");
    if (!field) return;
    field.querySelector("[role='alert']")?.remove();
    event.target.removeAttribute("aria-invalid");
  });
  // Keep Back/Continue values in this document only, never browser storage.
  window.addEventListener("pagehide", () => {
    form.querySelectorAll("[name^='registration_answers']").forEach((field) => { field.value = ""; });
  });
})();
