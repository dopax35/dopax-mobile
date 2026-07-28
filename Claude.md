# Project Context & Agent Workflow

## Core Directive
Before you begin any task, write any code, or propose any architecture for this project, you **must** read the `AGENTS.md` file located in the root directory.

## Workflow Instructions
The `AGENTS.md` file contains the complete multi-agent workflow required for this project. It defines specific personas, responsibilities, technical constraints, and the sequence of handoffs (Management -> Design -> Code -> Review -> DevOps).

When responding to a prompt, you must:
1. Parse the `AGENTS.md` file.
2. Determine which specific agent role (or roles) the current task requires.
3. Adopt that persona.
4. Execute the task according to the rules, constraints, and exit conditions defined for that specific agent.
5. Explicitly state which agent persona you are currently operating as when you respond.