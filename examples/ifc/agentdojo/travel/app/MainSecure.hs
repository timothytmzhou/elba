{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (runSecureAgent)
import Env (Env (..), defEnv)
import IFC (toLabeled, unlabel)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)
import Travel

agentEnv :: Env
agentEnv =
  $( addTools
       [ ''Email
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
       , 'unlabel
       , 'toLabeled
       , 'printf
       ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["IFC"]
      }

main :: IO ()
main = runSecureAgent agentEnv id
