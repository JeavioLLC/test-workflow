import { describe, it, expect } from 'vitest'
import { validateItemName } from './validateItemName.js'

describe('validateItemName', () => {
  it('accepts a valid name', () => {
    expect(validateItemName('widget')).toBe(true)
  })

  it('rejects an empty name', () => {
    expect(validateItemName('')).toBe(false)
  })

  it('accepts a name at the max length', () => {
    expect(validateItemName('a'.repeat(100))).toBe(true)
  })

  it('rejects a name over the max length', () => {
    expect(validateItemName('a'.repeat(101))).toBe(false)
  })
})
