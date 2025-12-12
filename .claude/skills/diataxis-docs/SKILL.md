---
name: diataxis-docs
description: Write documentation following the Diataxis framework. Use when creating tutorials, how-to guides, reference docs, or explanations for rules_tf2.
---

# Diataxis Documentation Framework

When writing documentation, follow the Diataxis framework which organizes content into four distinct types based on two axes:

## The Diataxis Compass

|              | Acquisition (Learning) | Application (Working) |
|--------------|------------------------|----------------------|
| **Action**   | Tutorial               | How-to Guide         |
| **Cognition**| Explanation            | Reference            |

**Two key questions to categorize content:**
1. Is this about **action** (doing) or **cognition** (understanding)?
2. Is this for **acquisition** (learning new skills) or **application** (using existing skills)?

---

## 1. Tutorials (Learning-oriented)

**Purpose:** Teach newcomers through guided, hands-on experience.

**Characteristics:**
- Learning-oriented, not task-oriented
- Teacher takes responsibility for student success
- Student learns by doing, not reading

**DO:**
- Show a clear destination (what learner will accomplish)
- Provide visible results at every step
- Use concrete, specific actions with expected outcomes
- Use first-person plural: "Let's create...", "Now we'll add..."
- Include observational cues: "You should see..."
- Keep it minimal - only what's needed to complete the lesson

**DON'T:**
- Include extended explanations or theory
- Offer multiple options or alternatives
- Make assumptions about learner knowledge
- Digress into tangential topics

**Structure:**
```markdown
# Tutorial: [What You'll Build]

## What you'll learn
- Bullet points of skills acquired

## Prerequisites
- Minimal list of requirements

## Steps

### Step 1: [Action]
First, let's...
[code/command]
You should see: [expected output]

### Step 2: [Action]
Now we'll...
```

---

## 2. How-to Guides (Task-oriented)

**Purpose:** Help users accomplish specific real-world tasks.

**Characteristics:**
- Goal-oriented, assumes user knows what they want
- Action only - no digression, explanation, or teaching
- Like a recipe: clear goal, specific steps

**DO:**
- Use problem-focused titles: "How to configure X for Y"
- Start where the task logically starts
- Use conditional imperatives: "If you need X, do Y"
- Maintain focus on the specific goal
- Link to reference docs for details

**DON'T:**
- Teach or explain concepts (link to explanations instead)
- Include complete reference information
- Add unnecessary background or context
- Define guides by tool capabilities rather than user needs

**Structure:**
```markdown
# How to [Accomplish Goal]

## Prerequisites
- What user must have ready

## Steps

1. [First action]
   ```
   command or code
   ```

2. [Second action]
   If you need [variant], instead do:
   ```
   alternative
   ```

## Verification
How to confirm success.

## See also
- Links to related guides
```

---

## 3. Reference (Information-oriented)

**Purpose:** Provide authoritative technical descriptions of the machinery.

**Characteristics:**
- Austere and factual - no opinions or speculation
- Consulted, not read sequentially
- Mirrors the product structure
- Like a map or encyclopedia entry

**DO:**
- Describe APIs, functions, options, parameters accurately
- Use consistent, standard patterns throughout
- Include concise usage examples
- Document errors, limitations, and warnings
- Keep descriptions factual and authoritative

**DON'T:**
- Include opinions or marketing language
- Add how-to guidance (link to how-to guides)
- Mix explanation with description
- Deviate from standard presentation patterns

**Structure:**
```markdown
# [Component/API Name]

Brief one-line description.

## Synopsis
```
usage pattern
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name`    | string | Yes    | What it does |

## Returns
What the function/rule returns.

## Example
```starlark
minimal_example()
```

## See also
- Related reference pages
```

---

## 4. Explanation (Understanding-oriented)

**Purpose:** Deepen understanding through context, history, and connections.

**Characteristics:**
- Higher-level perspective than other types
- Read away from active work (reflective)
- Joins concepts together
- Answers "Can you tell me about...?"

**DO:**
- Explain design decisions and reasoning
- Provide bigger picture context
- Discuss alternatives and trade-offs
- Connect to related topics
- Include appropriate opinions and judgments
- Use analogies to similar systems

**DON'T:**
- Include instructions or step-by-step procedures
- Add technical reference details
- Let content from other types creep in

**Structure:**
```markdown
# About [Topic]

## Overview
High-level introduction to the concept.

## Why [Topic] exists
The problem it solves, historical context.

## How it works
Conceptual explanation (not step-by-step).

## Design decisions
Why certain choices were made.

## Alternatives considered
Other approaches and why they weren't chosen.

## See also
- Related explanations
```

---

## rules_tf2 Documentation Structure

For this project, organize docs in `docs/src/` as:

```
docs/src/
├── SUMMARY.md              # mdbook table of contents
├── README.md               # Introduction
├── tutorials/
│   └── getting-started.md  # First tf_module tutorial
├── guides/
│   ├── provider-setup.md   # How to configure providers
│   └── testing.md          # How to run tests
├── reference/
│   ├── tf-module.md        # tf_module rule reference
│   ├── tf-runner.md        # tf_runner reference
│   └── extensions.md       # Module extensions reference
└── explanation/
    ├── architecture.md     # About the architecture
    └── providers.md        # About provider management
```

---

## Quick Decision Guide

When writing, ask yourself:

| If the user needs to... | Write a... |
|------------------------|------------|
| Learn a new skill from scratch | Tutorial |
| Accomplish a specific task they already understand | How-to Guide |
| Look up accurate technical details | Reference |
| Understand why something works the way it does | Explanation |

**Remember:** Keep types separate. Don't mix tutorial content into reference pages or explanations into how-to guides. Link between types instead.
