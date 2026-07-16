module Env
  ( Env (..),
    defEnv,
    Extension (..),
    ModuleName,
  )
where

import Language.Haskell.Interpreter (ModuleName)
import Language.Haskell.TH.Syntax (Extension (..))

-- | What the interpreted agent has in scope. A tool module contributes its
-- whole export list, docs included.
data Env = Env
  { modules :: [ModuleName],
    extensions :: [Extension],
    -- | Textual substitutions applied to types shown to the model, so a
    -- prompt can respect an alias that TypeRep rendering expands.
    typeAliases :: [(String, String)]
  }

defEnv :: Env
defEnv =
  Env
    { modules = [],
      extensions = [],
      typeAliases = []
    }
