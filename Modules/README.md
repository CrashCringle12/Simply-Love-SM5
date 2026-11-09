# Simply Love Modules
If one wants to write code that needs to run on specific screens, Simply Love defines this notion of "modules". This is useful if one wants to incorporate third-party code into the theme without needing to edit the Simply Love files directly.

## Inner Workings
When StepMania loads, we load the Lua files and supported folder entry points in the `/Modules` directory. These modules must define and return a table where each screen entry is a mapping from ScreenName to a single Actor/ActorFrame. These Actors will later get accumulated and added as child ActorFrames of ScreenSystemLayer. Every Actor must at least have a `ModuleCommand`. This is what gets executed whenever we load into a new screen.

When defining variables, remember to not have globals as they may pollute the global namespace.

For example, a module may look like the following:

```lua
local t = {}

t["ScreenSelectMusic"] = Def.ActorFrame {
    ModuleCommand=function(self)
        SCREENMAN:SystemMessage("hello from ScreenSelectMusic")
    end
}

t[Branch.GameplayScreen()] = Def.ActorFrame {
    ModuleCommand=function(self)
        SCREENMAN:SystemMessage("hello from ScreenGameplay")
    end
}

return t
```

## Module information

Modules can include a `ModuleInfo` table alongside their screen actors:

```lua
t.ModuleInfo = {
    Name = "My Module",
    Description = "Shows additional information during gameplay.",
    Author = "Your name",
    Version = "1.0",
    Updated = "2026-10-24",
    RequiredHosts = { "api.example.com", "chat.example.com" }
}
```

The module browser displays these fields. Use literal strings, including
Lua long strings for multiline descriptions, so the browser can read them
without executing the module. Missing fields display as Unknown; the list
uses the filename when Name is missing. The loader also exposes installed
metadata through `SL.ModuleInfo[filename]` (or the folder name for folder modules).

`RequiredHosts` lists the hosts the module may contact. These declarations
are shown with an exclamation mark; they do not grant network permission.
The browser also lists engine managers referenced directly in the entry
file, excluding comments and strings. This scan does not follow aliases
through helper files or resolve generated hostnames. A reference to
`NETWORK` without declared hosts is marked as missing host information.

Modules may be a single Lua file or a folder containing `default.lua` or a
Lua file with the same name as the folder. Supporting files stay in that
folder. Newly installed modules load on the next theme reload or game restart.

## Catalog provider

The browser's `Provider.lua` selects the catalog implementation. The current
`GitHub.lua` reads Simply-Love/Simply-Love-Modules. Replace that provider when
moving the catalog to another host; the screen and installer are independent
of GitHub.

Providers return a table with two functions:

- `List(callback)`: calls `callback(modules, errorKey, detail)`. Each module
  contains `Id`, `EntryPoint` (relative to Modules), `Files` (tables with a
  relative `Path`), and `Info` (the metadata above). Optional `Usage` contains
  `Managers` (a list of names) and `UsesNetwork` (a boolean) from a source scan.
- `Download(module, onFile, callback)`: downloads the selected module, calls
  `onFile(path, temporaryFile, index, total)` for each file, then calls
  `callback(success, errorKey, detail)`. Stop if `onFile` returns false.

Both functions return an operation with `Cancel()`. Providers pass requests
through `NETWORK` so the engine handles host permission. Browsing must not
execute module code.

The GitHub provider downloads each file by its listed blob SHA. Downloads
are staged under `Save/ModuleBrowser/`; supporting files are copied before
the entry point. Installed modules are not overwritten by the browser.

In the above example, we will simply SystemMessage a string once we load `ScreenSelectMusic` and `ScreenGameplay` respectively.
