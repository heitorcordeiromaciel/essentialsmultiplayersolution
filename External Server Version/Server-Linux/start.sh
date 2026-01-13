#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/ruby/bin/ruby" --disable-gems "$DIR/Server.rb"

