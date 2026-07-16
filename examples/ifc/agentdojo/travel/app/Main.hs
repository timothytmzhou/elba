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
