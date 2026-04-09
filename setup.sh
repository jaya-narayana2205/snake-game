#!/usr/bin/env bash
# =============================================================
# Snake Game — Git Repository Setup Script
# Initializes repo, commits all files, pushes to GitHub
# =============================================================

set -euo pipefail

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No color

# ---- Helper functions ----
info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()    { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---- Pre-flight checks ----
preflight() {
    info "Running pre-flight checks..."

    if ! command -v git &> /dev/null; then
        fail "git is not installed. Install it from https://git-scm.com"
    fi
    success "git found: $(git --version)"

    if [ -d ".git" ]; then
        warn "A git repository already exists in this directory."
        read -rp "  Reinitialize? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            fail "Aborted by user."
        fi
    fi
}

# ---- Get repo URL from user ----
get_repo_url() {
    if [ $# -ge 1 ] && [ -n "$1" ]; then
        REPO_URL="$1"
    else
        echo ""
        read -rp "Enter your GitHub repository URL: " REPO_URL
    fi

    if [ -z "$REPO_URL" ]; then
        fail "Repository URL cannot be empty."
    fi

    # Validate URL format (HTTPS or SSH)
    if [[ "$REPO_URL" =~ ^https://github\.com/.+/.+\.git$ ]] || \
       [[ "$REPO_URL" =~ ^git@github\.com:.+/.+\.git$ ]] || \
       [[ "$REPO_URL" =~ ^https://github\.com/.+/.+ ]]; then
        success "Repository URL accepted: $REPO_URL"
    else
        warn "URL does not match typical GitHub format."
        read -rp "  Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            fail "Aborted by user."
        fi
    fi
}

# ---- Step 1: Initialize git repo ----
init_repo() {
    info "Step 1/5 — Initializing git repository..."

    if git init; then
        success "Git repository initialized."
    else
        fail "Failed to initialize git repository."
    fi
}

# ---- Step 2: Stage all files ----
stage_files() {
    info "Step 2/5 — Staging all files..."

    # Create .gitignore if it doesn't exist
    if [ ! -f ".gitignore" ]; then
        warn ".gitignore not found — creating one."
        cat > .gitignore << 'GITIGNORE'
# Dependencies
node_modules/

# Environment
.env
.env.*

# OS files
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo

# Logs
*.log
GITIGNORE
        success ".gitignore created."
    fi

    if git add -A; then
        FILE_COUNT=$(git diff --cached --numstat | wc -l | tr -d ' ')
        success "Staged $FILE_COUNT file(s)."
    else
        fail "Failed to stage files."
    fi

    if [ "$FILE_COUNT" -eq 0 ]; then
        fail "No files to commit. Directory is empty."
    fi
}

# ---- Step 3: Commit ----
commit_files() {
    info "Step 3/5 — Committing files..."

    COMMIT_MSG="Initial Snake Game DevOps setup"

    if git commit -m "$COMMIT_MSG"; then
        success "Committed: \"$COMMIT_MSG\""
    else
        fail "Failed to commit files."
    fi
}

# ---- Step 4: Set remote origin ----
set_remote() {
    info "Step 4/5 — Setting remote origin..."

    # Remove existing origin if present
    if git remote get-url origin &> /dev/null; then
        warn "Remote 'origin' already exists — updating."
        if git remote set-url origin "$REPO_URL"; then
            success "Remote origin updated to: $REPO_URL"
        else
            fail "Failed to update remote origin."
        fi
    else
        if git remote add origin "$REPO_URL"; then
            success "Remote origin set to: $REPO_URL"
        else
            fail "Failed to add remote origin."
        fi
    fi
}

# ---- Step 5: Create main branch and push ----
push_code() {
    info "Step 5/5 — Creating 'main' branch and pushing..."

    # Rename current branch to main
    if git branch -M main; then
        success "Branch renamed to 'main'."
    else
        fail "Failed to rename branch to 'main'."
    fi

    info "Pushing to remote (this may prompt for authentication)..."

    if git push -u origin main; then
        success "Code pushed to origin/main."
    else
        echo ""
        warn "Push failed. Common fixes:"
        echo "  1. Check your GitHub credentials / SSH key"
        echo "  2. Ensure the repository exists on GitHub"
        echo "  3. Run: git push -u origin main  (manually)"
        fail "Failed to push to remote."
    fi
}

# ---- Summary ----
summary() {
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "  Repository : $REPO_URL"
    echo -e "  Branch     : main"
    echo -e "  Commit     : $(git log --oneline -1)"
    echo -e "  Files      : $(git ls-files | wc -l | tr -d ' ') tracked file(s)"
    echo ""
    echo -e "  ${CYAN}Next steps:${NC}"
    echo "  1. Add GitHub secrets (DOCKER_USERNAME, DOCKER_PASSWORD, SLACK_WEBHOOK_URL)"
    echo "  2. Update k8s/deployment.yml with your DockerHub image name"
    echo "  3. Push a change to 'main' to trigger the CI/CD pipeline"
    echo ""
}

# ---- Main ----
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   Snake Game — Repository Setup Script   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    preflight
    get_repo_url "${1:-}"
    echo ""
    init_repo
    stage_files
    commit_files
    set_remote
    push_code
    summary
}

main "$@"
