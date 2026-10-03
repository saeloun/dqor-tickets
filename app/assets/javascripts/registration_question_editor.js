document.querySelectorAll("[data-question-editor]").forEach((form) => {
  const type = form.querySelector("[name='question[type]']");
  const choices = form.querySelector("[data-question-choices]");
  if (!type || !choices) return;
  const update = () => {
    const active = type.value === "single_choice";
    choices.hidden = !active;
    choices.querySelector("textarea").disabled = !active;
  };
  type.addEventListener("change", update);
  update();
});
