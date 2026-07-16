{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (runInsecureAgent)
import Env (Env (..), defEnv)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)
import TravelTCB

agentEnv :: Env
agentEnv =
  $( addTools
       [ ''Email
       , ''CalendarEvent
       , 'getUserInformation
       , 'getAllHotelsInCity
       , 'getHotelsPrices
       , 'getRatingReviewsForHotels
       , 'getHotelsAddress
       , 'reserveHotel
       , 'getAllRestaurantsInCity
       , 'getCuisineTypeForRestaurants
       , 'getRestaurantsAddress
       , 'getRatingReviewsForRestaurants
       , 'getDietaryRestrictionsForAllRestaurants
       , 'getContactInformationForRestaurants
       , 'getPriceForRestaurants
       , 'checkRestaurantOpeningHours
       , 'reserveRestaurant
       , 'getAllCarRentalCompaniesInCity
       , 'getCarTypesAvailable
       , 'getRatingReviewsForCarRental
       , 'getCarFuelOptions
       , 'getCarRentalAddress
       , 'getCarPricePerDay
       , 'reserveCarRental
       , 'getFlightInformation
       , 'createCalendarEvent
       , 'searchCalendarEvents
       , 'getDayCalendarEvents
       , 'cancelCalendarEvent
       , 'sendEmail
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runInsecureAgent agentEnv
