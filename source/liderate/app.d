module liderate.app;

import std.stdio;

const string testSource = import("example.liderate");
class Portion
{
  bool isModule;
  string name;
  struct Ref
  {
    string portionName;
  }
  import std.variant: Algebraic;
  alias RefOrText = Algebraic!(Ref, string);
  RefOrText[] content;
  string text;
}

import liderate.treelan.parser;

Portion[string] portionsByName;
Portion[string] modulesByName;
void extractPortions(ParentNode root)
{
  void dfs(string currentPrefix, ParentNode parent)
  {
    import std.conv: text;
    import std.variant: visit;
    switch(parent.name)
      {
      case "section":
        currentPrefix ~= text(parent.parameters["id"], "/");
        foreach(child; parent.children)
          child.visit!((ParentNode node)
                       {
                         dfs(currentPrefix, node);
                       },
                       (string line)
                       {
                       });
        break;
      case "define":
        if ("id" in parent.parameters)
          {
            Portion portion = new Portion();
            with (portion)
              {
                isModule = false;
                name = currentPrefix ~ parent.parameters["id"];
                content = null;
                portion.text = null;
              }
            portionsByName[portion.name] = portion;
          }
        else if ("module" in parent.parameters)
          {
            Portion portion = new Portion();
            with (portion)
              {
                isModule = true;
                name = parent.parameters["module"];
                content = null;
                portion.text = null;
              }
            modulesByName[portion.name] = portion;
          }
        else
          assert(0, "A define without id or module parameter");
        break;
      case "portion":
        Portion portion;
        if ("id" in parent.parameters)
          {
            string id = parent.parameters["id"];
            string portionName;
            assert(id.length > 0);
            if (id[0] == '/')
              {
                portionName = id;
              }
            else
              {
                portionName = currentPrefix ~ id;
              }
            portion = portionsByName[portionName];
          }
        else if ("module" in parent.parameters)
          {
            portion = modulesByName[parent.parameters["module"]];
          }
        else
          assert(0, "A portion without module or id parameter");
        foreach(child; parent.children)
          {
            child.visit!((ParentNode node)
                         {
                           assert(node.name == "ref");
                           string id = node.parameters["id"];
                           assert(id.length > 0);
                           if (id[0] == '/')
                             {
                               portion.content ~= Portion.RefOrText(Portion.Ref(id));
                             }
                           else
                             {
                               portion.content ~= Portion.RefOrText(Portion.Ref(currentPrefix ~ id));
                             }
                         },
                         (string line)
                         {
                           portion.content ~= Portion.RefOrText(line);
                         });
          }
        break;
      case "root":
        foreach(child; parent.children)
          {
            child.visit!((ParentNode node)
                         {
                           dfs("/", node);
                         },
                         (string line){});
          }
        break;
      default:
        import std.conv: text;
        assert(0, text("Unknown node type ", parent.name));
      }
  }
  dfs("/", root);
}

enum ResolvingState
  {
   none,
   resolving,
   resolved,
  };
ResolvingState[Portion] resolvingState;
class ReferenceCycle: Exception
{
  this(string file = __FILE__, size_t line = __LINE__)
  {
    super("Cycle found in portion reference graph.", file, line);
  }
}
void resolveText(Portion portion)
{
  resolvingState.require(portion, ResolvingState.none);
  assert(resolvingState[portion] == ResolvingState.none);
  resolvingState[portion] = ResolvingState.resolving;
  foreach(line; portion.content)
    {
      import std.variant: visit;
      line.visit!((Portion.Ref reference)
                  {
                    Portion referencedPortion = portionsByName[reference.portionName];
                    resolvingState.require(referencedPortion, ResolvingState.none);
                    final switch(resolvingState[referencedPortion])
                      {
                      case ResolvingState.none:
                        resolveText(referencedPortion);
                        assert(resolvingState[referencedPortion] == ResolvingState.resolved);
                        portion.text ~= "\n" ~ referencedPortion.text;
                        break;
                      case ResolvingState.resolving:
                        throw new ReferenceCycle();
                      case ResolvingState.resolved:
                        portion.text ~= "\n" ~ referencedPortion.text;
                        break;
                      }
                  },
                  (string literalLine)
                  {
                    portion.text ~= "\n" ~ literalLine;
                  });
    }
  resolvingState[portion] = ResolvingState.resolved;
}

void main()
{
  ParentNode tree = parseTree(testSource);
  extractPortions(tree);
  import std.stdio: File;
  import std.file: mkdir;
  try
    {
      mkdir("gen");
    }
  catch(Throwable exception)
    {
    }
  foreach(moduleName, modulePortion; modulesByName)
    {
      resolveText(modulePortion);
      auto outputFile = File("gen/" ~ moduleName, "w");
      outputFile.write(modulePortion.text);
    }
}
