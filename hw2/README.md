# HW2: Traditional Software Design vs Function-as-a-Service

## Project Planning

### 1. System Choice
Choose one of the suggested systems or propose your own:
- Hospital management system
- Hotel management system
- Airport operations system
- University course management
- Other realistic system scenario

**Selected System:** [TO BE CHOSEN]

### 2. Required Operations/Services
List at least 7 meaningful operations for your chosen system:
1. 
2. 
3. 
4. 
5. 
6. 
7. 
8. (additional)

### 3. Implementation Plan

#### Part 1: Traditional Architecture
- Language: (C/C++/Python)
- Design approach: (monolithic/modular/service-based)
- Core components and structure

#### Part 2: FaaS Architecture
- Each operation becomes an independent stateless function
- Minimal dependencies between functions
- Clear function interfaces

#### Part 3: Feature Extension
- Proposed new feature: [TBD after implementations]
- Difficulty analysis for each architecture

#### Part 4: Performance Evaluation
- Profiling tool: perf (or alternative)
- Metrics to measure: execution time, CPU cycles, memory, context switches
- Test workload definition

## Directory Structure
```
hw2/
├── Traditional/          # Traditional implementation
├── FaaS/                 # FaaS implementation
├── script.sh             # Build/run/profile commands
├── report.pdf            # Final analysis (max 6 pages)
└── ids.pdf               # Team member names and IDs
```

## Submission Checklist
- [ ] System chosen and documented
- [ ] Operations/services defined
- [ ] Traditional implementation complete and working
- [ ] FaaS implementation complete and working
- [ ] Both architectures clearly different
- [ ] Feature extension design/partial implementation
- [ ] Performance profiling completed
- [ ] Report written (max 6 pages)
- [ ] script.sh with all build/run/profile commands
- [ ] HW2.zip created with required structure
