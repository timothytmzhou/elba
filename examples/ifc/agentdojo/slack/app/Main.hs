{-# LANGUAGE TemplateHaskell #-}

-- No policy agent app for the slack suite. The driver lives in InsecureApp.
module Main where

import Env (Env (..), defEnv)
import InsecureApp (runInsecureAgent)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import SlackTCB
import TH (addTools)
import Text.Printf (printf)
import WebTCB

agentEnv :: Env
agentEnv =
  $( addTools
       [ ''Body
       , ''Url
       , ''Message
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
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runInsecureAgent agentEnv
