#!/usr/bin/env sh
DIR="$(cd "$(dirname "$0")" && pwd)"
LIBDIR="$DIR/ruby/lib"

# --- Self-heal the bundled Ruby install -------------------------------
if [ -f "$DIR/ruby/bin/ruby" ] && [ ! -x "$DIR/ruby/bin/ruby" ]; then
  chmod +x "$DIR/ruby/bin/ruby" 2>/dev/null
fi

if [ -d "$LIBDIR" ]; then
  REAL_LIB=$(find "$LIBDIR" -maxdepth 1 -name 'libruby.so.*.*.*' -type f 2>/dev/null | head -n 1)
  if [ -n "$REAL_LIB" ]; then
    REAL_LIB_NAME=$(basename "$REAL_LIB")
    SHORT_NAME=$(echo "$REAL_LIB_NAME" | sed -E 's/^(libruby\.so\.[0-9]+\.[0-9]+)\.[0-9]+$/\1/')
    for LINK in "$LIBDIR/libruby.so" "$LIBDIR/$SHORT_NAME"; do
      if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
        rm -f "$LINK"
      fi
      [ -e "$LINK" ] || ln -s "$REAL_LIB_NAME" "$LINK" 2>/dev/null
    done
  fi
fi

BUNDLED_RUBYLIB=""
if [ -d "$DIR/ruby/lib/ruby" ]; then
  RUBY_VERSION_DIR=$(find "$DIR/ruby/lib/ruby" -maxdepth 1 -mindepth 1 -type d -regex '.*/[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null | head -n 1)
  if [ -z "$RUBY_VERSION_DIR" ]; then
    RUBY_VERSION_DIR=$(find "$DIR/ruby/lib/ruby" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -n 1)
  fi
  if [ -n "$RUBY_VERSION_DIR" ]; then
    ARCH_DIR=$(find "$RUBY_VERSION_DIR" -maxdepth 1 -type d \( -name '*-linux*' -o -name '*-gnu*' \) 2>/dev/null | head -n 1)
    BUNDLED_RUBYLIB="$RUBY_VERSION_DIR${ARCH_DIR:+:$ARCH_DIR}"
  fi
fi
# ------------------------------------------------------------------------

RUBY=""
if [ -x "$DIR/ruby/bin/ruby" ]; then
  BUNDLED_LD_LIBRARY_PATH="$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  if LD_LIBRARY_PATH="$BUNDLED_LD_LIBRARY_PATH" RUBYLIB="$BUNDLED_RUBYLIB" "$DIR/ruby/bin/ruby" -e 'require "socket"; require "zlib"; require "openssl"' >/dev/null 2>&1; then
    RUBY="$DIR/ruby/bin/ruby"
    export LD_LIBRARY_PATH="$BUNDLED_LD_LIBRARY_PATH"
    export RUBYLIB="$BUNDLED_RUBYLIB"
  else
    echo "Warning: the bundled Ruby install at $DIR/ruby looks broken (failed to load socket/zlib/openssl even after self-healing), falling back to system Ruby if available." >&2
  fi
fi
if [ -z "$RUBY" ]; then
  if command -v ruby >/dev/null 2>&1; then
    RUBY="ruby"
  else
    echo "No working Ruby found. Place a standalone Ruby install in $DIR/ruby, or install Ruby and make sure it's on your PATH."
    exit 1
  fi
fi
if [ -z "$RUBY" ]; then
  echo "Bundled Ruby failed and the fallback is temporarily disabled for testing."
  exit 1
fi
exec "$RUBY" --disable-gems "$DIR/Server.rb"
