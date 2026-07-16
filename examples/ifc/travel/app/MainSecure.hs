{-# LANGUAGE TemplateHaskell #-}

-- IFC-secured agent app for the travel suite. NOTE: the Travel policy
-- module is not implemented yet (every tool is `undefined`), so this
-- executable builds but fails at run time on the first tool call.
module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import IFC (DC, evalLIO, initialState, toLabeled, unlabel)
import InsecureApp (loadConfig, parseFlag)
import LLM (Config (..), defaultConfig)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import System.Environment (getArgs)
import TH (addTools)
import Text.Printf (printf)
import Travel

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- types
         ''Email
       , ''CalendarEvent
       , ''DC
       , ''DCLabeled
         -- user
       , 'getUserInformation
         -- hotels
       , 'getAllHotelsInCity
       , 'getHotelsPrices
       , 'getRatingReviewsForHotels
       , 'getHotelsAddress
       , 'reserveHotel
         -- restaurants
       , 'getAllRestaurantsInCity
       , 'getCuisineTypeForRestaurants
       , 'getRestaurantsAddress
       , 'getRatingReviewsForRestaurants
       , 'getDietaryRestrictionsForAllRestaurants
       , 'getContactInformationForRestaurants
       , 'getPriceForRestaurants
       , 'checkRestaurantOpeningHours
       , 'reserveRestaurant
         -- car rentals
       , 'getAllCarRentalCompaniesInCity
       , 'getCarTypesAvailable
       , 'getRatingReviewsForCarRental
       , 'getCarFuelOptions
       , 'getCarRentalAddress
       , 'getCarPricePerDay
       , 'reserveCarRental
         -- flights
       , 'getFlightInformation
         -- calendar + email
       , 'createCalendarEvent
       , 'searchCalendarEvents
       , 'getDayCalendarEvents
       , 'cancelCalendarEvent
       , 'sendEmail
         -- IFC API
       , 'unlabel
       , 'toLabeled
         -- prompt formatting
       , 'printf
       ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["IFC"]
      }

main :: IO ()
main = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  withBridge $ do
    prompt <- readPrompt
    let cfg = baseCfg {logPath = parseFlag "--log-path" args}
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalLIO agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
