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

-- | What the interpreted agent has in scope. A tool module contributes its whole export list.
data Env = Env
  { modules :: [ModuleName],
    extensions :: [Extension],
    -- | Textual substitutions applied to types shown to the model.
    typeAliases :: [(String, String)],
    -- | Filled by mkAgent so subagents reuse the parent resolution.
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
