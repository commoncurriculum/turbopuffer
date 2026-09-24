# Integration tests talk to turbopuffer, so they only run with an API key.
exclude = if System.get_env("TURBOPUFFER_API_KEY") in [nil, ""], do: [:integration], else: []
ExUnit.start(exclude: exclude)
