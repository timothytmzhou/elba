{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Trustworthy #-}

-- Insecure tool surface for the travel suite.
module TravelTCB (module TravelTCB, module AgentDojoTypes) where

import AgentDojoTypes
import Data.Map (Map)
import Tool (defTool, defTools)

type StringMap = Map String String

defTools
  [ defTool "getUserInformation" "get_user_information" [] [t|IO StringMap|]
  , defTool "getAllHotelsInCity" "get_all_hotels_in_city" ["city"] [t|String -> IO String|]
  , defTool "getHotelsPrices" "get_hotels_prices" ["hotel_names"] [t|[String] -> IO StringMap|]
  , defTool "getRatingReviewsForHotels" "get_rating_reviews_for_hotels" ["hotel_names"] [t|[String] -> IO StringMap|]
  , defTool "getHotelsAddress" "get_hotels_address" ["hotel_name"] [t|String -> IO StringMap|]
  , defTool "reserveHotel" "reserve_hotel" ["hotel", "start_day", "end_day"] [t|String -> String -> String -> IO String|]
  , defTool "getAllRestaurantsInCity" "get_all_restaurants_in_city" ["city"] [t|String -> IO String|]
  , defTool "getCuisineTypeForRestaurants" "get_cuisine_type_for_restaurants" ["restaurant_names"] [t|[String] -> IO StringMap|]
  , defTool "getRestaurantsAddress" "get_restaurants_address" ["restaurant_names"] [t|[String] -> IO StringMap|]
  , defTool "getRatingReviewsForRestaurants" "get_rating_reviews_for_restaurants" ["restaurant_names"] [t|[String] -> IO StringMap|]
  , defTool "getDietaryRestrictionsForAllRestaurants" "get_dietary_restrictions_for_all_restaurants" ["restaurant_names"] [t|[String] -> IO StringMap|]
  , defTool "getContactInformationForRestaurants" "get_contact_information_for_restaurants" ["restaurant_names"] [t|[String] -> IO StringMap|]
  , defTool "getPriceForRestaurants" "get_price_for_restaurants" ["restaurant_names"] [t|[String] -> IO (Map String Double)|]
  , defTool "checkRestaurantOpeningHours" "check_restaurant_opening_hours" ["restaurant_names"] [t|[String] -> IO StringMap|]
  , defTool "reserveRestaurant" "reserve_restaurant" ["restaurant", "start_time"] [t|String -> String -> IO String|]
  , defTool "getAllCarRentalCompaniesInCity" "get_all_car_rental_companies_in_city" ["city"] [t|String -> IO String|]
  , defTool "getCarTypesAvailable" "get_car_types_available" ["company_name"] [t|[String] -> IO (Map String [String])|]
  , defTool "getRatingReviewsForCarRental" "get_rating_reviews_for_car_rental" ["company_name"] [t|[String] -> IO StringMap|]
  , defTool "getCarFuelOptions" "get_car_fuel_options" ["company_name"] [t|[String] -> IO (Map String [String])|]
  , defTool "getCarRentalAddress" "get_car_rental_address" ["company_name"] [t|[String] -> IO StringMap|]
  , defTool "getCarPricePerDay" "get_car_price_per_day" ["company_name"] [t|[String] -> IO (Map String Double)|]
  , defTool "reserveCarRental" "reserve_car_rental" ["company", "start_time", "end_time"] [t|String -> String -> String -> IO String|]
  , defTool "getFlightInformation" "get_flight_information" ["departure_city", "arrival_city"] [t|String -> String -> IO String|]
  , defTool "createCalendarEvent" "create_calendar_event" ["title", "start_time", "end_time", "description", "participants"] [t|String -> String -> String -> String -> [String] -> IO CalendarEvent|]
  , defTool "searchCalendarEvents" "search_calendar_events" ["query", "date"] [t|String -> Maybe String -> IO [CalendarEvent]|]
  , defTool "getDayCalendarEvents" "get_day_calendar_events" ["day"] [t|String -> IO [CalendarEvent]|]
  , defTool "cancelCalendarEvent" "cancel_calendar_event" ["event_id"] [t|String -> IO String|]
  , defTool "sendEmail" "send_email" ["recipients", "subject", "body"] [t|[String] -> String -> String -> IO Email|]
  ]
