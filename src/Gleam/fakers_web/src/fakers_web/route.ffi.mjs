// location.hash の読み書きと hashchange の購読
export function get_hash() {
  return typeof location === "undefined" ? "" : location.hash;
}

export function set_hash(hash) {
  if (typeof location !== "undefined") location.hash = hash;
  return undefined;
}

export function on_hash_change(callback) {
  if (typeof window !== "undefined") {
    window.addEventListener("hashchange", () => callback(location.hash));
  }
  return undefined;
}
