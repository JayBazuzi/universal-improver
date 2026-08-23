# Universal Improver

I made a tool which I call the "universal improver". I am having a hard time explaining it, because I can come at it from so many different directions:

- A way to let AI coding agents loose on your code while minimizing risk of it breaking things
- ... while minimizing the number of tokens consumed
- ... while using older models
- A for people that don't trust or dislike AI to get benefit from it in a way they can accept
- A way to rein in the chaos of vibe coding
- Improve legacy code that we would previously have not bothered doing, by making it safe and cheap
- A program to run programs

# What it does

1. Run your "finder" tool to identify things that could be improved (warnings, code coverage, performance hotspots, whatever you can think of).
2. Run your "fixer" tool to address one of these items.
3. Verify that things are good.
4. Commit

# Tools you supply

Your **finder** tool is probably deterministic (non-AI) but is probably written with the help of AI. The output format can be anything you like, as long as it produces one item per line.

Your **fixer** tool probably calls AI to do some of the work, but is deterministic where possible. It is also probably written with the help of AI. Its only input is a line produced by the finder. Its only output is a commit message.

## Finder example

For example, I wrote a finder that identifies C# methods that build SQL queries but the methods are not called in the test project. It prints out one item per line like this:

```
path\to\CompanyManager.cs:219: CompanyManager.GetSearchUserQuery(userSearchFilter)
path\to\CompanyManager.cs:250:...
...
```

## Fixer example

And a fixer that prompts AI with:

```
Add a test case to path\to\QueryTests.cs for this issue:

    ${ISSUE}

that calls `VerifyQuery({METHOD_UNDER_TEST}(...))`
```

and limited permissions like:

```
    Read
    Edit(path\to\QueryTests.cs)
```

And then the fixer prints out a commit message:

```
echo ". t Add query pinning test for ..."
```

# Refactoring

If you have a deterministic, reliable command-line refactoring tool, you can give the AI permissions to run that tool but make no other edits. That gives you `. r` levels of safety.

If you don't have such a tool... ask Claude to write one for you.

# Command line:

```
Usage: universal-improver.sh <finder-tool> <fixer-tool> --count <N> [--build-and-test <build-and-test-tool>] [--random] [--parallel <N>]

  finder-tool: a command to identify issues to fix, outputting one per line
  fixer-tool:  a command that takes one line from finder-tool as input and,
               if it successfully addresses the issue, prints a commit message

  --count <N>             Number of items to attempt to fix before stopping (default: 1)
  --build-and-test <cmd>  Command to run after each fix to verify nothing broke;
                          if it fails, the fix is reverted and skipped (default: ./build-and-test.sh)
  --random                Pick items from the finder's output in random order (default: top-to-bottom)
  --parallel <N>          Fix up to N items concurrently (each in its own
                          worktree), merging successful fixes in turn
```



# Batching

You don't have to fix one warning at a time. You might fix one *class* of issue at a time. For example, instead of fixing one lint issue at a time the finder might print out the list of disabled lint rules and then the fixer tries to enable and fix one whole lint rule + enable the rule.

# Some types of issues to address

- build warnings
- lint / static analysis stuff (including custom analyzers you ask Claude to write)
- functions with low test coverage
- functions with high code complexity
- profiler data identifying performance hotspots

# Thoughts on the use of AI

Some people are hugely enthusiastic about using AI coding agents, and will happily just tell Claude to dangerously skip permissions and write the next feature and ship it without further inspection. For them, if the results have a flaw that should be address with a better LLM or a better prompt or higher "effort".

Some people are the opposite: they see the problems with the above approach and think it's imprudent to let AI edit code, and we programmers should be using our expertise and judgement to write code without AI. For them, the flaws in AI-produced code are a sign that we shouldn't be using AI at all. Or they see the impact of "hyper scale" AI data centers on communities and water and energy and don't want to support that. And so on - there are plenty of reasons someone might be anti-AI.

This tool takes a different approach, that draws on both of those points of view. It says that AI is actually quite good at certain things but we don't want to ask AI to do anything that could be done well without AI. It's about making tools to do as much of the work as we can, and constraining the AI to only do the parts that we can't put in tools.

The result is better code, fewer defects, fewer tokens used, older models, less energy consumption, less motivation for AI companies to pour so many resources into LLM development.
