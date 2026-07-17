{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

module TravelTCB
  ( EmailId (..)
  , Email (..)
  , CalendarEvent (..)
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

import Bridge (callPy)
import Data.Aeson (object, (.=))
import Data.Map (Map)
import WorkspaceTCB (CalendarEvent (..), Email (..), EmailId (..))

-- | Many travel tools return a JSON object keyed by name (e.g. hotel ->
-- price string). Decoded as a string-keyed map.
type StringMap = Map String String

----------------------------------------------------------------
-- User
----------------------------------------------------------------

-- | Get the user information, could be: first name, last name, ID number, email, phone number, address, passport number, bank account number, credit card number. These information are used for booking hotels, restaurants, car rentals, and flights.
getUserInformation :: IO StringMap
getUserInformation = callPy "get_user_information" (object [])

----------------------------------------------------------------
-- Hotels
----------------------------------------------------------------

-- | Get all hotels in the given city.
getAllHotelsInCity :: String -> IO String
getAllHotelsInCity city = callPy "get_all_hotels_in_city" (object ["city" .= city])

-- | Get all hotels within the given budget, should be within the price range.
getHotelsPrices :: [String] -> IO StringMap
getHotelsPrices names = callPy "get_hotels_prices" (object ["hotel_names" .= names])

-- | Get the rating and reviews for the given hotels.
getRatingReviewsForHotels :: [String] -> IO StringMap
getRatingReviewsForHotels names = callPy "get_rating_reviews_for_hotels" (object ["hotel_names" .= names])

-- | Get the address of the given hotel.
getHotelsAddress :: String -> IO StringMap
getHotelsAddress name = callPy "get_hotels_address" (object ["hotel_name" .= name])

-- | Makes a reservation for a hotel with the provided details..
reserveHotel :: String -> String -> String -> IO String
reserveHotel hotel startDay endDay =
  callPy "reserve_hotel" (object ["hotel" .= hotel, "start_day" .= startDay, "end_day" .= endDay])

----------------------------------------------------------------
-- Restaurants
----------------------------------------------------------------

-- | Get all restaurants in the given city.
getAllRestaurantsInCity :: String -> IO String
getAllRestaurantsInCity city = callPy "get_all_restaurants_in_city" (object ["city" .= city])

-- | Get the cuisine type of the given restaurants, could be: Italian, Chinese, Indian, Japanese.
getCuisineTypeForRestaurants :: [String] -> IO StringMap
getCuisineTypeForRestaurants names =
  callPy "get_cuisine_type_for_restaurants" (object ["restaurant_names" .= names])

-- | Get the address of the given restaurants.
getRestaurantsAddress :: [String] -> IO StringMap
getRestaurantsAddress names = callPy "get_restaurants_address" (object ["restaurant_names" .= names])

-- | Get the rating and reviews for the given restaurants.
getRatingReviewsForRestaurants :: [String] -> IO StringMap
getRatingReviewsForRestaurants names =
  callPy "get_rating_reviews_for_restaurants" (object ["restaurant_names" .= names])

-- | Get the dietary restrictions of the given restaurants, could be: Vegetarian, Vegan, Gluten-free, Dairy-free.
getDietaryRestrictionsForAllRestaurants :: [String] -> IO StringMap
getDietaryRestrictionsForAllRestaurants names =
  callPy "get_dietary_restrictions_for_all_restaurants" (object ["restaurant_names" .= names])

-- | Get the contact information of the given restaurants.
getContactInformationForRestaurants :: [String] -> IO StringMap
getContactInformationForRestaurants names =
  callPy "get_contact_information_for_restaurants" (object ["restaurant_names" .= names])

-- | Get the price per person of the given restaurants.
getPriceForRestaurants :: [String] -> IO (Map String Double)
getPriceForRestaurants names = callPy "get_price_for_restaurants" (object ["restaurant_names" .= names])

-- | Get the openning hours of the given restaurants, check if the restaurant is open.
checkRestaurantOpeningHours :: [String] -> IO StringMap
checkRestaurantOpeningHours names =
  callPy "check_restaurant_opening_hours" (object ["restaurant_names" .= names])

-- | Makes a reservation for a restaurant with the provided details.
reserveRestaurant :: String -> String -> IO String
reserveRestaurant restaurant startTime =
  callPy "reserve_restaurant" (object ["restaurant" .= restaurant, "start_time" .= startTime])

----------------------------------------------------------------
-- Car rentals
----------------------------------------------------------------

-- | Get all car rental companies in the given city.
getAllCarRentalCompaniesInCity :: String -> IO String
getAllCarRentalCompaniesInCity city =
  callPy "get_all_car_rental_companies_in_city" (object ["city" .= city])

-- | Get the car types available for the given car rental companies.
getCarTypesAvailable :: [String] -> IO (Map String [String])
getCarTypesAvailable names = callPy "get_car_types_available" (object ["company_name" .= names])

-- | Get the rating and reviews for the given car rental companies.
getRatingReviewsForCarRental :: [String] -> IO StringMap
getRatingReviewsForCarRental names =
  callPy "get_rating_reviews_for_car_rental" (object ["company_name" .= names])

-- | Get the fuel options of the given car rental companies.
getCarFuelOptions :: [String] -> IO (Map String [String])
getCarFuelOptions names = callPy "get_car_fuel_options" (object ["company_name" .= names])

-- | Get the address of the given car rental companies.
getCarRentalAddress :: [String] -> IO StringMap
getCarRentalAddress names = callPy "get_car_rental_address" (object ["company_name" .= names])

-- | Get the price per day of the given car rental companies.
getCarPricePerDay :: [String] -> IO (Map String Double)
getCarPricePerDay names = callPy "get_car_price_per_day" (object ["company_name" .= names])

-- | Makes a reservation for a car rental with the provided details.
reserveCarRental :: String -> String -> String -> IO String
reserveCarRental company startTime endTime =
  callPy "reserve_car_rental" (object ["company" .= company, "start_time" .= startTime, "end_time" .= endTime])

----------------------------------------------------------------
-- Flights
----------------------------------------------------------------

-- | Get the flight information from the departure city to the arrival city.
getFlightInformation :: String -> String -> IO String
getFlightInformation departureCity arrivalCity =
  callPy "get_flight_information" (object ["departure_city" .= departureCity, "arrival_city" .= arrivalCity])

----------------------------------------------------------------
-- Calendar + email (shared with the workspace suite)
----------------------------------------------------------------

-- | Creates a new calendar event with the given details and adds it to the calendar.
-- It also sends an email to the participants with the event details.
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

-- | Searches calendar events that match the given query in the tile or the description. If provided, filters events by date.
searchCalendarEvents :: String -> String -> IO [CalendarEvent]
searchCalendarEvents query date =
  callPy "search_calendar_events" (object ["query" .= query, "date" .= dateArg])
  where
    dateArg = if null date then Nothing else Just date

-- | Returns the appointments for the given @day@. Returns a list of dictionaries with informations about each meeting.
getDayCalendarEvents :: String -> IO [CalendarEvent]
getDayCalendarEvents day = callPy "get_day_calendar_events" (object ["day" .= day])

-- | Cancels the event with the given @event_id@. The event will be marked as canceled and no longer appear in the calendar.
-- It will also send an email to the participants notifying them of the cancellation.
cancelCalendarEvent :: String -> IO String
cancelCalendarEvent eid = callPy "cancel_calendar_event" (object ["event_id" .= eid])

-- | Sends an email with the given @body@ to the given @address@. Returns a dictionary with the email details.
sendEmail :: [String] -> String -> String -> IO Email
sendEmail recipients subject body =
  callPy "send_email" (object ["recipients" .= recipients, "subject" .= subject, "body" .= body])
