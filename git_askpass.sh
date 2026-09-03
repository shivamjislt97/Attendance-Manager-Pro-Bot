#!/bin/sh
# Git push ke liye credential helper — secret is file me NAHI hai.
# GH_PAT env var (.env se, gitignored) se aata hai.
exec echo "$GH_PAT"
