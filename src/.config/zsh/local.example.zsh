# Машинно-зависимые настройки. Скопируйте в local.zsh — он не коммитится:
#   cp ~/.config/zsh/local.example.zsh ~/.config/zsh/local.zsh
#
# Здесь собрано то, что было в старых ~/.zshrc и ~/.zprofile этой машины.

# Корпоративный корневой сертификат для Node (npm, npx, MCP-серверы)
# export NODE_EXTRA_CA_CERTS="$HOME/st-ca-root.pem"

# Редактор для VS Code вместо nvim
# export EDITOR="code --wait"
# export VISUAL="code --wait"

# Освободившийся PATH-префикс pyenv/python.org — если понадобится, раскомментируйте.
# По умолчанию Python управляется через uv (см. docs/install.md).
# path=("/Library/Frameworks/Python.framework/Versions/3.11/bin" $path)

# Локальные бинарники инструментов
# path=("$HOME/.opencode/bin" $path)

# Корпоративные прокси (если понадобятся)
# export HTTPS_PROXY="http://proxy.example:8080"
# export HTTP_PROXY="$HTTPS_PROXY"
# export NO_PROXY="127.0.0.1,localhost,::1"

# uv: использовать только управляемые интерпретаторы, не системный
# export UV_PYTHON_PREFERENCE=only-managed

# Остальное — по вкусу
# export FZF_DEFAULT_OPTS="--height 50% --layout=reverse --border"
