---
name: code-walkthrough
description: Deeply analyzes all source code in the current directory and generates a comprehensive, step-by-step walkthrough article. The generated Markdown document guides the reader through the implementation principles with Mermaid flowcharts for better understanding, and pairs every technical point with the corresponding code snippets. Use this skill when the user wants a detailed, readable, tutorial-style explanation of how the entire codebase works.
---

# Code Walkthrough Generator

## Overview
This skill reads all code in the current directory, understands its architecture and implementation details, and produces a highly readable, tutorial-style Markdown article. The article must guide the reader step-by-step through the codebase, explaining the core principles, and must include Mermaid flowcharts and corresponding code snippets for every point made.

## Workflow

When triggered, you MUST follow these steps exactly:

1. **Information Gathering**
   - Use the `Glob` or `Bash` (e.g., `find . -type f -not -path "*/\.*" -not -path "*/node_modules/*"`) tools to list all relevant source code files in the current directory.
   - Use the `Read` tool to read the contents of all key source code files. Understand the file structure, dependencies, entry points, and core logic.

2. **Architecture and Logic Analysis**
   - Mentally map out the system architecture and data flow.
   - Identify the core modules, key functions, and how they interact.

3. **Document Generation**
   - Generate a comprehensive Markdown article (`walkthrough.md` or similar appropriate name).
   - **Mandatory Declaration:** At the very top of the generated document, you MUST insert the model declaration as per the global prompt rules. For Chinese documents: `> **注：** 本文档由 **[Current Actual Model Name]** 模型自动生成。`
   - **Structure:**
     - **Title:** A clear, engaging title for the codebase.
     - **Introduction:** High-level overview of what the code does.
     - **Architecture Flowchart:** A clear `mermaid` diagram (graph or sequenceDiagram) illustrating the overall architecture or data flow.
     - **Step-by-step Walkthrough:** Break down the code into logical sections (e.g., Initialization, Core Processing, Output).
     - **Code Snippets:** For *every* point made in the walkthrough, provide the relevant, concise code snippet using standard markdown code blocks with the correct language tag. DO NOT dump entire files; only show the relevant parts. Explain *why* the code does what it does.
     - **Conclusion:** A brief summary of the implementation.

4. **Output Presentation**
   - Inform the user that the walkthrough has been generated and provide the path to the Markdown file.
   - Use the `TaskUpdate` tool to mark the task as completed.

## Mermaid Guidelines
- Keep Mermaid diagrams simple and clean.
- Use `graph TD` or `sequenceDiagram` primarily.
- Ensure all nodes and edges have clear, understandable labels in quotes (e.g., `A["Start"] --> B["Process"]`).

## Code Snippet Guidelines
- Always include the file path above or within the code block for context.
- Keep snippets focused on the logic being explained. Use `...` to omit irrelevant boilerplate within a function or class.
