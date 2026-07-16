{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (ifcTools, runSecureAgent)
import Env (Env (..), defEnv)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)
import Travel

agentEnv :: Env
agentEnv =
  $( addTools $
     ifcTools
       ++ [ ''Email
         , ''CalendarEvent
         , 'getUserInformation
         , 'getAllHotelsInCity
         , 'getHotelsPrices
         , 'reserveHotel
         , 'getAllRestaurantsInCity
         , 'getPriceForRestaurants
         , 'reserveRestaurant
         , 'getFlightInformation
         , 'createCalendarEvent
         , 'sendEmail
         , 'printf
         ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["IFC"]
      }

main :: IO ()
main = runSecureAgent agentEnv id
