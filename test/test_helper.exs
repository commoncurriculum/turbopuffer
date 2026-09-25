# GitHub Actions sets a missing secret to an empty string, so treat empty as unset.
if System.get_env("TURBOPUFFER_API_KEY") in [nil, ""] do
  if System.get_env("CI") do
    raise """
    The :integration tests write to real turbopuffer namespaces, so set TURBOPUFFER_API_KEY.
    Each test uses its own namespaces and deletes them when it finishes.
    In CI, add it as the repository's TURBOPUFFER_API_KEY Actions secret.
    """
  end

  ExUnit.start(exclude: [:integration])
else
  ExUnit.start()
end
