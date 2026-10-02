const form = document.getElementById("branding-draft-form");
if (form) {
  document.documentElement.classList.add("enhanced-editor");
  const status = document.getElementById("draft-status");
  const error = document.getElementById("editor-error");
  const fingerprint = () =>
    JSON.stringify(
      [...new FormData(form)].map(([key, value]) => [
        key,
        value instanceof File
          ? [value.name, value.size, value.name ? value.lastModified : 0]
          : value,
      ]),
    );
  const initial = fingerprint();
  let busy = false,
    leaving = false;
  const dirty = () => fingerprint() !== initial;
  const changed = () => {
    status.textContent = dirty()
      ? "Unsaved edits · preview shows saved draft"
      : "Saved draft · public activation off";
  };
  const showError = (message) => {
    error.textContent = message;
    error.hidden = false;
    error.focus();
  };
  form.addEventListener("input", changed);
  form.addEventListener("change", changed);
  window.addEventListener("beforeunload", (event) => {
    if (dirty() && !leaving) {
      event.preventDefault();
      event.returnValue = "";
    }
  });
  document.querySelectorAll("[data-color-for]").forEach((swatch) => {
    swatch.disabled = false;
    const hex = document.getElementById(swatch.dataset.colorFor);
    swatch.addEventListener("input", () => {
      hex.value = swatch.value;
      changed();
    });
    hex.addEventListener("input", () => {
      if (/^#[0-9a-f]{6}$/i.test(hex.value)) swatch.value = hex.value;
    });
  });
  document.querySelectorAll(".image-choice").forEach((card) => {
    const input = card.querySelector('input[type="file"]');
    const selected = card.querySelector(".selection");
    let url;
    function clear() {
      if (url) URL.revokeObjectURL(url);
      url = null;
      input.value = "";
      selected.hidden = true;
      selected.querySelector("img").removeAttribute("src");
      changed();
    }
    selected.querySelector("button").addEventListener("click", () => {
      clear();
      input.focus();
    });
    input.addEventListener("change", () => {
      if (url) URL.revokeObjectURL(url);
      const file = input.files[0];
      if (!file) {
        clear();
        return;
      }
      if (
        !["image/png", "image/jpeg", "image/webp"].includes(file.type) ||
        file.size > 1048576
      ) {
        clear();
        showError(
          "Choose a PNG, JPEG or WebP image no larger than 1 MB. Other edits are still here.",
        );
        return;
      }
      url = URL.createObjectURL(file);
      selected.querySelector("img").src = url;
      selected.querySelector("img").alt =
        `Selected ${input.id.replace("branding_", "")} preview`;
      selected.querySelector("span").textContent =
        `${file.name} · selected, not saved`;
      selected.hidden = false;
      const remove = card.querySelector('input[type="checkbox"]');
      if (remove) remove.checked = false;
      changed();
    });
  });
  const dialog = document.getElementById("saved-preview-dialog");
  const frame = dialog.querySelector("iframe");
  let opener;
  const close = () => {
    if (history.state?.brandingPreview) history.back();
    else {
      dialog.close();
      opener?.focus();
    }
  };
  window.addEventListener("popstate", () => {
    if (dialog.open) {
      dialog.close();
      opener?.focus();
    }
  });
  document.getElementById("close-preview").addEventListener("click", close);
  dialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    close();
  });
  document.querySelectorAll("[data-saved-preview]").forEach((link) =>
    link.addEventListener("click", (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
        return;
      event.preventDefault();
      opener = link;
      frame.src = link.href;
      history.pushState({ brandingPreview: true }, "", "#saved-preview");
      dialog.showModal();
      document.getElementById("close-preview").focus();
    }),
  );
  frame.addEventListener("load", () => {
    const doc = frame.contentDocument;
    if (!doc) return;
    doc.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        close();
      }
    });
    doc.querySelectorAll("a").forEach((link) => {
      if (new URL(link.href).pathname === new URL(form.action).pathname)
        link.addEventListener("click", (event) => {
          event.preventDefault();
          close();
        });
      else if (
        new URL(link.href).pathname === new URL(frame.src).pathname &&
        new URL(link.href).hash
      ) {
        link.addEventListener("click", (event) => {
          event.preventDefault();
          doc
            .getElementById(new URL(link.href).hash.slice(1))
            ?.scrollIntoView();
        });
      } else {
        link.target = "_blank";
        link.rel = "noopener";
      }
    });
  });
  document.querySelectorAll(".workspace form").forEach((mutation) =>
    mutation.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (busy) return;
      if (mutation !== form && dirty()) {
        showError(
          "Save your draft before publishing or restoring a publication. Your unsaved edits are still here.",
        );
        return;
      }
      const data = new FormData(mutation);
      busy = true;
      error.hidden = true;
      document
        .querySelectorAll(
          ".workspace input, .workspace select, .workspace button, .editor-actions button",
        )
        .forEach((button) => (button.disabled = true));
      status.textContent = "Saving to the server…";
      try {
        const response = await fetch(mutation.action, {
          method: "POST",
          body: data,
          credentials: "same-origin",
          headers: { Accept: "application/json" },
        });
        const result = response.headers
          .get("content-type")
          ?.includes("application/json")
          ? await response.json()
          : null;
        if (!response.ok || !result?.redirect)
          throw new Error(
            result?.error ||
              "The save could not be confirmed. Your edits are still here. Check your session and the saved draft before retrying.",
          );
        leaving = true;
        location.assign(result.redirect);
      } catch (failure) {
        showError(`${failure.message} Your entered values have been kept.`);
        busy = false;
        document
          .querySelectorAll(
            ".workspace input, .workspace select, .workspace button, .editor-actions button",
          )
          .forEach((button) => (button.disabled = false));
        changed();
      }
    }),
  );
}
