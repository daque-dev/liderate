module liderate.app;

void main(string[] args)
{
  import liderate.simplelan;
  import std.stdio;
  import std.array;
  import std.container;

  auto file = File(args[1]);
  Node tree = null;
  SList!Node fragmentNodes = SList!Node();
  parseString(tree, fragmentNodes, file.byLine.join("\n").idup);
  file.close();

  writeln(tree);
  if (2 < args.length)
    {
      switch(args[2])
        {
        case "tangle":
          tangle(fragmentNodes);
          break;
        case "weave-markdown":
          writeln("weaving markdown");
          weaveMarkdown(tree, "weaved.md");
          break;
        case "weave-latex":
          writeln("weaving latex");
          weaveLatex(tree, "weaved.tex");
          break;
        default:
          assert(0);
        }
    }
}

import liderate.simplelan;
import std.container;
import std.typecons;
void tangle(SList!Node fragmentNodes)
{
  import std.stdio;
  writeln("Running tangle over ", fragmentNodes[]);
  class TangleError: Throwable
  {
    this(string msg)
    {
      super(msg);
    }
  }
  struct Line
  {
    bool isRef;
    long indentation;
    string content;
  }
  Line[][string] linesPerFragment;
  string[string] fragmentFileName;
  foreach(node; fragmentNodes)
    {
      switch(node.type)
        {
        case NodeType.fileFragmentDefinition:
          fragmentFileName[node.id] = node.value;
          goto case NodeType.fragmentDefinition;
        case NodeType.fragmentDefinition:
          linesPerFragment[node.id] = [];
          break;
        default:
          break;
        }
    }
  foreach(node; fragmentNodes)
    {
      switch(node.type)
        {
        case NodeType.fragmentAddition:
          if (node.value !in linesPerFragment)
            throw new TangleError("tried adding to fragment without definition");
          foreach(child; node.children)
            {
              auto indentation = child.indentationLevel - node.indentationLevel;
              switch(child.type)
                {
                case NodeType.simpleLine:
                  linesPerFragment[node.value] ~= Line(false, indentation, child.value);
                  break;
                case NodeType.reference:
                  linesPerFragment[node.value] ~= Line(true, indentation, child.value);
                  break;
                default:
                  assert(0);
                }
            }
          break;
        default:
          break;
        }
    }
  enum ResolvingState
    {
      notStarted, started, finished
    }
  string[string] textPerFragment;
  ResolvingState[string] state;
  foreach(fragmentName; linesPerFragment.keys)
    {
      textPerFragment[fragmentName] = "";
      state[fragmentName] = ResolvingState.notStarted;
    }
  void dfs(string fragment)
  {
    assert(fragment in state);
    assert(fragment in linesPerFragment);
    assert(fragment in textPerFragment);
    assert(state[fragment] == ResolvingState.notStarted);
    foreach(line; linesPerFragment[fragment])
      {
        import std.array;
        import std.range;
        import std.algorithm;
        import std.conv;
        string addIndentation(string str)
        {
          return iota(0, line.indentation).map!(i => " ").join ~ str;
        }
        if (line.isRef)
          {
            assert(line.content in state);
            if (state[line.content] == ResolvingState.started)
              throw new TangleError("Cycle found in fragment reference graph");
            if (state[line.content] == ResolvingState.notStarted)
              dfs(line.content);
            assert(state[line.content] == ResolvingState.finished);
            textPerFragment[fragment] ~= textPerFragment[line.content]
              .split("\n") // split per line
              .map!addIndentation.join("\n") // add to each line the indentation and rejoin
              ~ "\n"; // add the final line break
          }
        else
          {
            textPerFragment[fragment] ~= addIndentation(line.content) ~ "\n";
          }
      }
    state[fragment] = ResolvingState.finished;
  }
  foreach(fileFragmentName; fragmentFileName.keys)
    {
      if (state[fileFragmentName] == ResolvingState.notStarted)
        dfs(fileFragmentName);
      import std.stdio;
      writeln("Text for ", fileFragmentName);
      writeln(textPerFragment[fileFragmentName]);
    }
  foreach(fileFragmentName; fragmentFileName.keys)
    {
      import std.array: split, join, array;
      import std.algorithm: filter, map;
      import std.process: executeShell, escapeShellCommand;
      auto fileName = fragmentFileName[fileFragmentName];
      auto directory = "tangled/" ~ fileName
        .split("/")
        .filter!(dir => dir.length > 0).array[0 .. $ - 1]
        .map!(dir => dir ~ "/")
        .join;
      executeShell(escapeShellCommand("mkdir", "-p", directory));
      File outputFile = File("tangled/" ~ fileName, "w");
      outputFile.write(textPerFragment[fileFragmentName]);
      outputFile.close();
    }
}

string[string] searchLongNames(Node tree)
{
  string[string] sectionLongName;

  switch(tree.type)
    {
    case NodeType.fragmentDefinition:
    case NodeType.fileFragmentDefinition:
      sectionLongName[tree.id] = tree.value;
      break;
    default:
      break;
    }
  foreach(child; tree.children)
    {
      auto subResult = searchLongNames(child);
      foreach(k, v; subResult)
        sectionLongName[k] = v;
    }

  return sectionLongName;
}

void weaveMarkdown(Node tree, string outputFileName)
{
  import std.stdio: File;
  import std.algorithm;
  import std.range;
  import std.process: executeShell, escapeShellCommand;
  auto directory = "weaved/";
  executeShell(escapeShellCommand("mkdir", "-p", directory));
  auto outputFile = File(directory ~ outputFileName, "w");
  scope(exit) outputFile.close();

  string[string] sectionLongName = searchLongNames(tree);

  void dfs(Node node, int sectionLevel)
  {

    final switch(node.type)
      {
      case NodeType.fragmentAddition:
        iota(0, sectionLevel).each!(i => outputFile.write("#"));
        if (sectionLevel > 0) outputFile.writeln("< "
                                                 , sectionLongName[node.value]
                                                 , " > += ");
        const minIndentation = node.children.map!(c => c.indentationLevel).fold!min;
        foreach(child; node.children)
          {
            const indentation = child.indentationLevel - minIndentation;
            outputFile.write("\t");
            iota(0, indentation).each!(i => outputFile.write(" "));
            if (child.type == NodeType.reference)
              outputFile.writeln("> ", sectionLongName[child.value]);
            else
              outputFile.writeln(child.value);
          }
        break;
      case NodeType.section:
      case NodeType.fileFragmentDefinition:
      case NodeType.fragmentDefinition:
        iota(0, sectionLevel).each!(i => outputFile.write("#"));
        if (sectionLevel > 0)
        switch(node.type)
          {
          case NodeType.section:
            outputFile.writeln(node.value);
            break;
          case NodeType.fileFragmentDefinition:
            outputFile.writeln("Source file \"", node.value, "\"");
            break;
          case NodeType.fragmentDefinition:
            outputFile.writeln("< ", node.value, " > = ");
            break;
          default: assert(0);
          }
        foreach(child; node.children)
          {
            dfs(child, sectionLevel + 1);
          }
        break;
      case NodeType.simpleLine:
        outputFile.writeln(node.value);
        break;
      case NodeType.reference:
      case NodeType.invalid:
        assert(0);
      }
  }
  dfs(tree, 0);
}

void weaveLatex(Node tree, string fileName)
{
  import std.stdio;
  import std.algorithm;
  import std.process;
  auto directory = "weaved/";
  executeShell(escapeShellCommand("mkdir", "-p", directory));
  auto outputFile = File(directory ~ fileName, "w");
  scope(exit) outputFile.close();
  auto fragmentLongName = searchLongNames(tree);
  string[][string] linksToSection;
  int currentLinkId = 1;
  void linksPass(Node node)
  {
    if (node.type == NodeType.simpleLine)
      {
        import std.array;
        import std.algorithm;
        import std.conv;
        auto links = node.value
          .split
          .filter!(word => word.length > 0)
          .filter!(word => word.startsWith("#"))
          .map!(word => word[1 .. $]);
        foreach(link; links)
          linksToSection[link] ~= text("link", currentLinkId++);
      }
    foreach(child; node.children)
      linksPass(child);
  }
  linksPass(tree);
  auto parentStack = SList!Node();
  currentLinkId = 1;
  void dfs(Node node, int depth)
  {
    parentStack.insert(node);
    scope(exit) parentStack.removeFront;
    import std.array;
    import std.utf;
    auto currentSection = ("/" ~ parentStack[].array.reverse[1 .. $]
      .filter!(node => node.type == NodeType.section)
      .map!(node => node.id ~ "/")
      .join)[0 .. $ - 1]
      .toUTF8;
    void writeSection()
    {
      auto sectionName = node.value;
      enum latexSectionName = ["chapter",
                               "section",
                               "subsection",
                               "subsubsection",
                               "paragraph",
                               "subparagraph"
                               ];
      if (depth >= 0 && depth < latexSectionName.length)
        {
          outputFile.writeln("\\", latexSectionName[depth], "{", sectionName, "}");
          outputFile.writeln("\\hypertarget{", currentSection, "}{}");
        }
      else
        throw new Throwable("Invalid depth for LaTeX weaving");
      if (auto links = currentSection in linksToSection)
        if ((*links).length > 0)
          {
            outputFile.writeln("\\paragraph{Referenced by}");
            foreach(link; *links)
              outputFile.write("\\hyperlink{", link, "}{", link[4 .. $], "} ");
            outputFile.writeln;
            outputFile.writeln;
          }
    }
    final switch(node.type)
      {
      case NodeType.section:
        if (depth >= 0) writeSection();
        foreach(child; node.children)
          dfs(child, depth + 1);
        break;
      case NodeType.fragmentAddition:
        outputFile.writeln("\\subparagraph{\\emph{\\textless ", fragmentLongName[node.value], " \\textgreater += }}");
        outputFile.writeln("\\begin{verbatim}");
        const minIndentation = node.children.map!(c => c.indentationLevel).fold!min;
        foreach(child; node.children)
          {
            const indentation = child.indentationLevel - minIndentation;
            foreach(i; 0 .. indentation) outputFile.write(" ");
            if (child.type == NodeType.reference)
              outputFile.writeln("<", fragmentLongName[child.value], ">");
            else
              outputFile.writeln(child.value);
          }
        outputFile.writeln("\\end{verbatim}");
        break;
      case NodeType.fragmentDefinition:
        outputFile.writeln("\\subparagraph{\\emph{Code Fragment: ", node.value, "}}");
        foreach(child; node.children)
          dfs(child, depth);
        break;
      case NodeType.fileFragmentDefinition:
        outputFile.writeln("\\subparagraph{\\emph{File: ", node.value, "}}");
        foreach(child; node.children)
          dfs(child, depth);
        break;
      case NodeType.simpleLine:
        import std.array;
        import std.utf;
        auto line = node.value;
        foreach(word; line.split(" "))
          if (word.length > 0)
          {
            if (word.startsWith("#"))
              {
                import std.conv;
                auto linkString = "link" ~ to!string(currentLinkId++);
                outputFile.write("\\hypertarget{"
                                 , linkString
                                 , "}{\\hyperlink{"
                                 , word[1 .. $], "}{", word[1 .. $], "}} ");
              }
            else
              {
                outputFile.write(word, " ");
              }
          }
        return outputFile.writeln;
      case NodeType.invalid:
      case NodeType.reference:
        assert(0);
      }
  }
  enum preamble = `
\documentclass{book}
\title{Program}
\renewcommand{\familydefault}{\sfdefault}
\usepackage{hyperref}
\hypersetup{
  colorlinks = true,
  linkcolor = blue,
}
\begin{document}
\maketitle {}
\tableofcontents{}
`;
  outputFile.writeln(preamble);
  dfs(tree, -1);
  outputFile.writeln(`\end{document}`);
}
