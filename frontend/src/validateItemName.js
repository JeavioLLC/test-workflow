const MAX_NAME_LENGTH = 100

export function validateItemName(name) {
  return Boolean(name) && name.length <= MAX_NAME_LENGTH
}
