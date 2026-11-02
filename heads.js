async function loadHeads() {
  const { data, error } = await supabaseClient
    .from("heads")
    .select("id, parent_id, name, sort_order")
    .order("sort_order");
  if (error) throw error;

  const byParent = {};
  data.forEach((h) => {
    const key = h.parent_id || "root";
    if (!byParent[key]) byParent[key] = [];
    byParent[key].push(h);
  });

  return {
    all: data,
    mainHeads: byParent["root"] || [],
    childrenOf(id) {
      return byParent[id] || [];
    },
    nameOf(id) {
      const h = data.find((x) => x.id === id);
      return h ? h.name : "";
    }
  };
}

function populateSelect(selectEl, items, placeholder) {
  selectEl.innerHTML = "";
  const opt0 = document.createElement("option");
  opt0.value = "";
  opt0.textContent = placeholder;
  selectEl.appendChild(opt0);
  items.forEach((item) => {
    const opt = document.createElement("option");
    opt.value = item.id;
    opt.textContent = item.name;
    selectEl.appendChild(opt);
  });
}
