module Env
  ( Env (..),
    defEnv,
    Extension (..),
    ModuleName,
    ResolvedTool (..),
  )
where

import Language.Haskell.Interpreter (ModuleName)
import Language.Haskell.TH.Syntax (Extension (..))

-- | One export of a tool module, shown to the model with its Haddock.
data ResolvedTool = ResolvedTool
  { toolName :: String,
    toolIsValue :: Bool,
    toolDoc :: Maybe String
  }

-- | What the interpreted agent has in scope. A tool module contributes its
-- whole export list, docs included.
data Env = Env
  { modules :: [ModuleName],
    extensions :: [Extension],
    -- | Textual substitutions applied to types shown to the model, so a
    -- prompt can respect an alias that TypeRep rendering expands.
    typeAliases :: [(String, String)],
    -- | Filled by mkAgent so a subagent spawned from interpreted code
    -- reuses the parent's resolution instead of resolving again.
    resolvedTools :: Maybe [ResolvedTool]
  }

defEnv :: Env
defEnv =
  Env
    { modules = [],
      extensions = [],
      typeAliases = [],
      resolvedTools = Nothing
    }
