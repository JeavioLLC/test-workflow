import { describe, it, expect } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import App from './App.jsx'

describe('App', () => {
  it('renders the welcome message', () => {
    render(<App />)

    expect(
      screen.getByText('Hello from the sample CI/CD application'),
    ).toBeInTheDocument()
  })

  it('adds an item to the list on valid submit', () => {
    render(<App />)

    fireEvent.change(screen.getByLabelText('Item name'), {
      target: { value: 'widget' },
    })
    fireEvent.click(screen.getByText('Add item'))

    expect(screen.getByText('widget')).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('rejects an empty item name', () => {
    render(<App />)

    fireEvent.click(screen.getByText('Add item'))

    expect(screen.getByRole('alert')).toHaveTextContent('invalid item name')
  })

  it('rejects a name over 100 characters', () => {
    render(<App />)

    fireEvent.change(screen.getByLabelText('Item name'), {
      target: { value: 'a'.repeat(101) },
    })
    fireEvent.click(screen.getByText('Add item'))

    expect(screen.getByRole('alert')).toHaveTextContent('invalid item name')
  })

  it('appends multiple items in order', () => {
    render(<App />)
    const input = screen.getByLabelText('Item name')
    const submit = screen.getByText('Add item')

    fireEvent.change(input, { target: { value: 'first' } })
    fireEvent.click(submit)
    fireEvent.change(input, { target: { value: 'second' } })
    fireEvent.click(submit)

    const items = screen.getAllByRole('listitem').map((el) => el.textContent)
    expect(items).toEqual(['first', 'second'])
  })
})
