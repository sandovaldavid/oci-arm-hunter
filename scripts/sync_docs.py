#!/usr/bin/env python3
import os
import re

REPO_URL = "https://github.com/sandovaldavid/oci-arm-hunter"
DOCS_DIR = "docs"

def sync_readme():
    with open("README.md", "r", encoding="utf-8") as f:
        content = f.read()

    # Prepend Jekyll front matter
    front_matter = (
        "---\n"
        "layout: default\n"
        "title: Documentation\n"
        "description: Complete documentation and reference guide for oci-arm-hunter.\n"
        "---\n\n"
    )
    
    # Replace relative links:
    def replace_link(match):
        text, url = match.groups()
        if url.startswith(("http://", "https://", "mailto:", "#", "index", "getting-started", "readme", "changelog")):
            return f"[{text}]({url})"
        # If it's a markdown file that we have in docs, we can link to it relative (without .md)
        if url == "README.md":
            return f"[{text}](readme)"
        if url == "CHANGELOG.md":
            return f"[{text}](changelog)"
        # Otherwise, link to github
        return f"[{text}]({REPO_URL}/blob/main/{url})"

    # Match [text](url)
    updated_content = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', replace_link, content)
    
    with open(os.path.join(DOCS_DIR, "readme.md"), "w", encoding="utf-8") as f:
        f.write(front_matter + updated_content)
    print("✓ Synchronized README.md to docs/readme.md")

def sync_changelog():
    with open("CHANGELOG.md", "r", encoding="utf-8") as f:
        content = f.read()

    front_matter = (
        "---\n"
        "layout: default\n"
        "title: Changelog\n"
        "description: Version history and release notes for oci-arm-hunter.\n"
        "---\n\n"
    )

    with open(os.path.join(DOCS_DIR, "changelog.md"), "w", encoding="utf-8") as f:
        f.write(front_matter + content)
    print("✓ Synchronized CHANGELOG.md to docs/changelog.md")

if __name__ == "__main__":
    os.makedirs(DOCS_DIR, exist_ok=True)
    sync_readme()
    sync_changelog()
