{-# LANGUAGE TemplateHaskell #-}

-- No policy agent app for the travel suite. The driver lives in InsecureApp.
module Main where

import Env (Env (..), defEnv)
import InsecureApp (runInsecureAgent)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)
import TravelTCB

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- shared types
         ''Email
       , ''CalendarEvent
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
         -- prompt formatting
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runInsecureAgent agentEnv
