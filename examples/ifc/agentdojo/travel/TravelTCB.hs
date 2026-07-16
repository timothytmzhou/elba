{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- | Insecure tool surface for AgentDojo's @travel@ suite (hotels,
-- restaurants, car rentals, flights, plus a little calendar + email).
-- Most travel tools return human-readable strings or string maps rather
-- than structured records, so the bindings are thin. This is the
-- no-policy surface used by @agentdojo-travel@; the IFC-secured surface is
-- left to be written by hand (see travel/policy/Policy.hs).
module TravelTCB
  ( module AgentDojoTypes
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

import AgentDojoTypes
import Bridge (callPy)
import Data.Aeson (object, (.=))
import Data.Map (Map)

-- | Many travel tools return a JSON object keyed by name (e.g. hotel ->
-- price string). Decoded as a string-keyed map.
type StringMap = Map String String

----------------------------------------------------------------
-- User
----------------------------------------------------------------

-- | The current user's stored booking information (name, email, passport,
-- payment details, ...), keyed by field label.
getUserInformation :: IO StringMap
getUserInformation = callPy "get_user_information" (object [])

----------------------------------------------------------------
-- Hotels
----------------------------------------------------------------

getAllHotelsInCity :: String -> IO String
getAllHotelsInCity city = callPy "get_all_hotels_in_city" (object ["city" .= city])

getHotelsPrices :: [String] -> IO StringMap
getHotelsPrices names = callPy "get_hotels_prices" (object ["hotel_names" .= names])

getRatingReviewsForHotels :: [String] -> IO StringMap
getRatingReviewsForHotels names = callPy "get_rating_reviews_for_hotels" (object ["hotel_names" .= names])

getHotelsAddress :: String -> IO StringMap
getHotelsAddress name = callPy "get_hotels_address" (object ["hotel_name" .= name])

-- | Reserve a hotel. @startDay@/@endDay@: ISO "YYYY-MM-DD".
reserveHotel :: String -> String -> String -> IO String
reserveHotel hotel startDay endDay =
  callPy "reserve_hotel" (object ["hotel" .= hotel, "start_day" .= startDay, "end_day" .= endDay])

----------------------------------------------------------------
-- Restaurants
----------------------------------------------------------------

getAllRestaurantsInCity :: String -> IO String
getAllRestaurantsInCity city = callPy "get_all_restaurants_in_city" (object ["city" .= city])

getCuisineTypeForRestaurants :: [String] -> IO StringMap
getCuisineTypeForRestaurants names =
  callPy "get_cuisine_type_for_restaurants" (object ["restaurant_names" .= names])

getRestaurantsAddress :: [String] -> IO StringMap
getRestaurantsAddress names = callPy "get_restaurants_address" (object ["restaurant_names" .= names])

getRatingReviewsForRestaurants :: [String] -> IO StringMap
getRatingReviewsForRestaurants names =
  callPy "get_rating_reviews_for_restaurants" (object ["restaurant_names" .= names])

getDietaryRestrictionsForAllRestaurants :: [String] -> IO StringMap
getDietaryRestrictionsForAllRestaurants names =
  callPy "get_dietary_restrictions_for_all_restaurants" (object ["restaurant_names" .= names])

getContactInformationForRestaurants :: [String] -> IO StringMap
getContactInformationForRestaurants names =
  callPy "get_contact_information_for_restaurants" (object ["restaurant_names" .= names])

getPriceForRestaurants :: [String] -> IO (Map String Double)
getPriceForRestaurants names = callPy "get_price_for_restaurants" (object ["restaurant_names" .= names])

checkRestaurantOpeningHours :: [String] -> IO StringMap
checkRestaurantOpeningHours names =
  callPy "check_restaurant_opening_hours" (object ["restaurant_names" .= names])

-- | Reserve a restaurant. @startTime@: ISO "YYYY-MM-DD HH:MM".
reserveRestaurant :: String -> String -> IO String
reserveRestaurant restaurant startTime =
  callPy "reserve_restaurant" (object ["restaurant" .= restaurant, "start_time" .= startTime])

----------------------------------------------------------------
-- Car rentals
----------------------------------------------------------------

getAllCarRentalCompaniesInCity :: String -> IO String
getAllCarRentalCompaniesInCity city =
  callPy "get_all_car_rental_companies_in_city" (object ["city" .= city])

getCarTypesAvailable :: [String] -> IO (Map String [String])
getCarTypesAvailable names = callPy "get_car_types_available" (object ["company_name" .= names])

getRatingReviewsForCarRental :: [String] -> IO StringMap
getRatingReviewsForCarRental names =
  callPy "get_rating_reviews_for_car_rental" (object ["company_name" .= names])

getCarFuelOptions :: [String] -> IO (Map String [String])
getCarFuelOptions names = callPy "get_car_fuel_options" (object ["company_name" .= names])

getCarRentalAddress :: [String] -> IO StringMap
getCarRentalAddress names = callPy "get_car_rental_address" (object ["company_name" .= names])

getCarPricePerDay :: [String] -> IO (Map String Double)
getCarPricePerDay names = callPy "get_car_price_per_day" (object ["company_name" .= names])

-- | Reserve a car rental. @startTime@/@endTime@: ISO "YYYY-MM-DD HH:MM".
reserveCarRental :: String -> String -> String -> IO String
reserveCarRental company startTime endTime =
  callPy "reserve_car_rental" (object ["company" .= company, "start_time" .= startTime, "end_time" .= endTime])

----------------------------------------------------------------
-- Flights
----------------------------------------------------------------

getFlightInformation :: String -> String -> IO String
getFlightInformation departureCity arrivalCity =
  callPy "get_flight_information" (object ["departure_city" .= departureCity, "arrival_city" .= arrivalCity])

----------------------------------------------------------------
-- Calendar + email (shared with the workspace suite)
----------------------------------------------------------------

createCalendarEvent :: String -> String -> String -> String -> [String] -> IO CalendarEvent
createCalendarEvent title startTime endTime description participants =
  callPy
    "create_calendar_event"
    ( object
        [ "title" .= title
        , "start_time" .= startTime
        , "end_time" .= endTime
        , "description" .= description
        , "participants" .= participants
        ]
    )

searchCalendarEvents :: String -> String -> IO [CalendarEvent]
searchCalendarEvents query date =
  callPy "search_calendar_events" (object ["query" .= query, "date" .= dateArg])
  where
    dateArg = if null date then Nothing else Just date

getDayCalendarEvents :: String -> IO [CalendarEvent]
getDayCalendarEvents day = callPy "get_day_calendar_events" (object ["day" .= day])

cancelCalendarEvent :: String -> IO String
cancelCalendarEvent eid = callPy "cancel_calendar_event" (object ["event_id" .= eid])

sendEmail :: [String] -> String -> String -> IO Email
sendEmail recipients subject body =
  callPy "send_email" (object ["recipients" .= recipients, "subject" .= subject, "body" .= body])
