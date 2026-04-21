#!/usr/bin/env python3

import os
import sys
from pathlib import Path


def rel_target(target: Path, link_path: Path) -> str:
    return os.path.relpath(target, link_path.parent)


def ensure_symlink(link_path: Path, target: Path) -> None:
    desired = rel_target(target, link_path)

    if link_path.is_symlink():
        if os.readlink(link_path) == desired:
            return
        link_path.unlink()
    elif link_path.exists():
        print(f"[ax]   skip skill: {link_path.name} (exists, not a symlink)")
        return

    link_path.symlink_to(desired)
    print(f"[ax]   linked skill: {link_path.name}")


def cleanup_stale_project_links(claude_skills_dir: Path, valid_project_skills: set[str]) -> None:
    for child in claude_skills_dir.iterdir():
        if not child.is_symlink():
            continue
        target = os.readlink(child)
        if not target.startswith("../../.agents/skills/"):
            continue
        skill_name = Path(target).name
        if skill_name not in valid_project_skills:
            child.unlink()
            print(f"[ax]   removed stale skill symlink: {child.name}")


def sync(project_root: Path) -> int:
    claude_skills_dir = project_root / ".claude" / "skills"
    claude_skills_dir.mkdir(parents=True, exist_ok=True)
    valid_project_skills = set()

    ax_skill_dir = project_root / ".ax" / "skills" / "ax"
    if ax_skill_dir.is_dir():
        ensure_symlink(claude_skills_dir / "ax", ax_skill_dir)

    project_skills_dir = project_root / ".agents" / "skills"
    if project_skills_dir.is_dir():
        for skill_dir in sorted(project_skills_dir.iterdir()):
            if not skill_dir.is_dir():
                continue
            if skill_dir.name == "ax":
                continue
            if not (skill_dir / "SKILL.md").is_file():
                continue
            valid_project_skills.add(skill_dir.name)
            ensure_symlink(claude_skills_dir / skill_dir.name, skill_dir)

    cleanup_stale_project_links(claude_skills_dir, valid_project_skills)
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: sync_claude_skills.py <project_root>", file=sys.stderr)
        return 1
    return sync(Path(sys.argv[1]).resolve())


if __name__ == "__main__":
    raise SystemExit(main())
