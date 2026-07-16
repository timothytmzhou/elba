{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (runInsecureAgent)
import Env (Env (..), defEnv)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import SlackTCB
import TH (addTools)
import Text.Printf (printf)
import WebTCB

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- messages
         ''Body
       , ''Url
       , ''Message
         -- values
       , 'getChannels
       , 'addUserToChannel
       , 'readChannelMessages
       , 'readInbox
       , 'sendDirectMessage
       , 'sendChannelMessage
       , 'inviteUserToSlack
       , 'removeUserFromSlack
       , 'getUsersInChannel
       , 'getWebpage
       , 'postWebpage
         -- prompt formatting
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runInsecureAgent agentEnv
