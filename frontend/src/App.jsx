import { useState } from 'react'
import { validateItemName } from './validateItemName.js'

function App() {
  const [items, setItems] = useState([])
  const [name, setName] = useState('')
  const [error, setError] = useState('')

  function handleSubmit(event) {
    event.preventDefault()

    if (!validateItemName(name)) {
      setError('invalid item name')
      return
    }

    setItems((prev) => [...prev, { id: prev.length + 1, name }])
    setName('')
    setError('')
  }

  return (
    <main>
      <h1>Hello from the sample CI/CD application</h1>
      <form onSubmit={handleSubmit}>
        <label htmlFor="item-name">Item name</label>
        <input
          id="item-name"
          value={name}
          onChange={(event) => setName(event.target.value)}
        />
        <button type="submit">Add item</button>
      </form>
      {error && <p role="alert">{error}</p>}
      <ul>
        {items.map((item) => (
          <li key={item.id}>{item.name}</li>
        ))}
      </ul>
    </main>
  )
}

export default App
