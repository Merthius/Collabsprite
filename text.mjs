// Never split a surrogate pair at a display-name boundary: the native Lua
// decoder deliberately rejects lone surrogates in incoming JSON.
export function label(value, limit) {
  return Array.from(String(value).toWellFormed().replace(/[\x00-\x1f\x7f]/g, '')).slice(0, limit).join('');
}
