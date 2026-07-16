{-# LANGUAGE Trustworthy #-}

module Travel
  ( DC
  , DCLabeled
  , Email
  , CalendarEvent
  , StringMap
    -- * User
  , getUserInformation
    -- * Hotels
  , getAllHotelsInCity
  , getHotelsPrices
  , getRatingReviewsForHotels
  , getHotelsAddress
  , reserveHotel
    -- * Restaurants
  , getAllRestaurantsInCity
  , getCuisineTypeForRestaurants
  , getRestaurantsAddress
  , getRatingReviewsForRestaurants
  , getDietaryRestrictionsForAllRestaurants
  , getContactInformationForRestaurants
  , getPriceForRestaurants
  , checkRestaurantOpeningHours
  , reserveRestaurant
    -- * Car rentals
  , getAllCarRentalCompaniesInCity
  , getCarTypesAvailable
  , getRatingReviewsForCarRental
  , getCarFuelOptions
  , getCarRentalAddress
  , getCarPricePerDay
  , reserveCarRental
    -- * Flights
  , getFlightInformation
    -- * Calendar + email
  , createCalendarEvent
  , searchCalendarEvents
  , getDayCalendarEvents
  , cancelCalendarEvent
  , sendEmail
  ) where

import AgentDojoTypes (CalendarEvent, Email)
import Data.Map (Map)
import IFC (DC, DCLabeled)

type StringMap = Map String String

getUserInformation :: DC (DCLabeled StringMap)
getUserInformation = undefined

getAllHotelsInCity :: String -> DC (DCLabeled String)
getAllHotelsInCity = undefined

getHotelsPrices :: [String] -> DC (DCLabeled StringMap)
getHotelsPrices = undefined

getRatingReviewsForHotels :: [String] -> DC (DCLabeled StringMap)
getRatingReviewsForHotels = undefined

getHotelsAddress :: String -> DC (DCLabeled StringMap)
getHotelsAddress = undefined

reserveHotel :: DCLabeled String -> String -> String -> DC ()
reserveHotel = undefined

getAllRestaurantsInCity :: String -> DC (DCLabeled String)
getAllRestaurantsInCity = undefined

getCuisineTypeForRestaurants :: [String] -> DC (DCLabeled StringMap)
getCuisineTypeForRestaurants = undefined

getRestaurantsAddress :: [String] -> DC (DCLabeled StringMap)
getRestaurantsAddress = undefined

getRatingReviewsForRestaurants :: [String] -> DC (DCLabeled StringMap)
getRatingReviewsForRestaurants = undefined

getDietaryRestrictionsForAllRestaurants :: [String] -> DC (DCLabeled StringMap)
getDietaryRestrictionsForAllRestaurants = undefined

getContactInformationForRestaurants :: [String] -> DC (DCLabeled StringMap)
getContactInformationForRestaurants = undefined

getPriceForRestaurants :: [String] -> DC (DCLabeled (Map String Double))
getPriceForRestaurants = undefined

checkRestaurantOpeningHours :: [String] -> DC (DCLabeled StringMap)
checkRestaurantOpeningHours = undefined

reserveRestaurant :: DCLabeled String -> String -> DC ()
reserveRestaurant = undefined

getAllCarRentalCompaniesInCity :: String -> DC (DCLabeled String)
getAllCarRentalCompaniesInCity = undefined

getCarTypesAvailable :: [String] -> DC (DCLabeled (Map String [String]))
getCarTypesAvailable = undefined

getRatingReviewsForCarRental :: [String] -> DC (DCLabeled StringMap)
getRatingReviewsForCarRental = undefined

getCarFuelOptions :: [String] -> DC (DCLabeled (Map String [String]))
getCarFuelOptions = undefined

getCarRentalAddress :: [String] -> DC (DCLabeled StringMap)
getCarRentalAddress = undefined

getCarPricePerDay :: [String] -> DC (DCLabeled (Map String Double))
getCarPricePerDay = undefined

reserveCarRental :: DCLabeled String -> String -> String -> DC ()
reserveCarRental = undefined

getFlightInformation :: String -> String -> DC (DCLabeled String)
getFlightInformation = undefined

createCalendarEvent :: DCLabeled String -> String -> String -> DCLabeled String -> [String] -> DC ()
createCalendarEvent = undefined

searchCalendarEvents :: String -> String -> DC (DCLabeled [CalendarEvent])
searchCalendarEvents = undefined

getDayCalendarEvents :: String -> DC (DCLabeled [CalendarEvent])
getDayCalendarEvents = undefined

cancelCalendarEvent :: String -> DC ()
cancelCalendarEvent = undefined

sendEmail :: [String] -> DCLabeled String -> DCLabeled String -> DC ()
sendEmail = undefined
