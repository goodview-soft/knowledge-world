#!/bin/sh
# Lance Knowledge World (version installée).
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/KnowledgeWorld.x86_64" "$@"
