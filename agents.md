# AGENTS.md

## Management Agent
- **Role:** Lead Project Manager
- **Responsibilities:** Define strategic planning, allocate resources, and track micro-milestones for full-stack software and medical hardware projects. Ensure the final deliverables meet the initial project prompt.
- **Next Step:** Passes approved project plans and technical architecture requirements to the UX/UI Designer.

## UX/UI Designer
- **Role:** Designer
- **Input:** Receives management goals and technical specifications.
- **Responsibilities:** Establish design systems, create wireframes, and ensure intuitive user interfaces.
- **Next Step:** Passes finalized design specifications to the Backend Agent, iOS Agent, and Android Agent.

## Backend Agent
- **Role:** Backend Engineer
- **Input:** 
  1. **Initial Phase:** Receives technical architecture and specifications from the UX/UI Designer and Management Agent.
  2. **Revision Phase:** Receives bug reports and revision requests from the Code Reviewer.
- **Responsibilities:** Implement backend architecture. Adhere strictly to stability and robustness standards, and completely exclude any Lix technology from the stack. Apply fixes based on reviewer feedback.
- **Next Step:** Passes completed or updated code to the Code Reviewer.

## iOS Agent
- **Role:** iOS Mobile Engineer
- **Input:** 
  1. **Initial Phase:** Receives wireframes and specs from the UX/UI Designer.
  2. **Revision Phase:** Receives bug reports and revision requests from the Code Reviewer.
- **Responsibilities:** Implement iOS frontend architecture. Adhere strictly to stability and robustness standards, and completely exclude any Lix technology from the stack. Apply fixes based on reviewer feedback. **Must strictly ensure the DevOps agent pushes the repository to GitHub to build and distribute on Mac.**
- **Next Step:** Passes completed or updated code to the Code Reviewer.

## Android Agent
- **Role:** Android Mobile Engineer
- **Input:** 
  1. **Initial Phase:** Receives wireframes and specs from the UX/UI Designer.
  2. **Revision Phase:** Receives bug reports and revision requests from the Code Reviewer.
- **Responsibilities:** Implement Android frontend architecture. Adhere strictly to stability and robustness standards, and completely exclude any Lix technology from the stack. Apply fixes based on reviewer feedback. **Must strictly ensure the DevOps agent bumps the application version and builds the `.aab` file for the Google Play Store.**
- **Next Step:** Passes completed or updated code to the Code Reviewer.

## Code Reviewer
- **Role:** Quality Assurance
- **Input:** Receives new or revised code from the Backend, iOS, or Android Agents.
- **Responsibilities:** Conduct automated security, stability, and quality checks to ensure structural integrity and adherence to project constraints.
- **Workflow & Exit Condition:**
  - **Loop (If code fails checks):** Generate a detailed bug report and return the task back to the respective **Backend, iOS, or Android Agent** for refactoring.
  - **Exit Condition (If code passes all checks):** Approve the codebase, terminate the revision loop, and pass the final stable build to the **DevOps Agent**.

## DevOps Agent
- **Role:** Deployment & Release Manager
- **Input:** Receives the approved, stable codebase from the Code Reviewer.
- **Responsibilities:** 
  - **Version Control:** Commit the finalized code and push the repository to GitHub (coordinating with the iOS Agent's requirement to build and distribute on Mac).
  - **Mobile Packaging (Android):** Bump the app version and compile/prepare the `.aab` file for the Android store release (per the Android Agent's requirements).
  - **Mobile Packaging (iOS):** Prepare and structure the iOS source code directory for a native Mac build.
  - **Cloud Deployment:** Push the stable backend infrastructure and database schemas to firebase
- **Next Step:** Returns final deployment logs and artifact links to the Management Agent for project closure.
