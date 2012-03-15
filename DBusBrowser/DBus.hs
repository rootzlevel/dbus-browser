{-# LANGUAGE ScopedTypeVariables, OverloadedStrings #-}
module DBusBrowser.DBus 
       ( module DBus.Types
       , Client
       , DBus.Introspection.Method(..)
       , DBus.Introspection.Signal(..)
       , DBus.Introspection.Property(..)
       , DBus.Introspection.Parameter(..)
       , getBusses
       , getNames
       , getObjects
       , getInterfaces
       , Iface(..)
       , getMembers
       ) where

import Prelude hiding (catch)

import DBus.Client hiding (Method)
import DBus.Client.Simple (connectSystem, connectSession)
import DBus.Message hiding (Signal)
import DBus.Types
import DBus.Connection
import DBus.Introspection

import qualified Data.Set as S
import Data.Maybe
import qualified Data.Text as T
import Data.List (sort,find)

import Control.Exception

getBusses :: IO (Maybe Client, Maybe Client)
getBusses = do
  system <- fmap Just connectSystem `catch` \(e :: ConnectionError) -> return Nothing
  session <- fmap Just connectSession `catch` \(e :: ConnectionError) -> return Nothing
  return (system, session)

getNames :: Client -> IO [BusName]
getNames client = do
  res <- call_ client $ MethodCall {
    methodCallPath = "/org/freedesktop/DBus",
    methodCallMember = "ListNames",
    methodCallInterface = Just "org.freedesktop.DBus",
    methodCallDestination = Just "org.freedesktop.DBus",
    methodCallFlags = S.empty,
    methodCallBody = [] }

  let names = fromMaybe [] $ fromVariant (methodReturnBody res !! 0)

  return $ sort $ map busName_ names

getObjects :: Client -> BusName -> IO [ObjectPath]
getObjects client service = collectObjects client service "/"
 
introspect :: Client -> BusName -> ObjectPath -> IO (Maybe Object)
introspect client service path = do
  res <- call_ client $ MethodCall {
    methodCallPath = path,
    methodCallMember = "Introspect",
    methodCallInterface = Just "org.freedesktop.DBus.Introspectable",
    methodCallDestination = Just service,
    methodCallFlags = S.empty,
    methodCallBody = [] }

  let xml = fromVariant $ methodReturnBody res !! 0
      object = fromXML path =<< xml

  return object

collectObjects :: Client -> BusName -> ObjectPath -> IO [ObjectPath]
collectObjects client service path = do
  res <- introspect client service path
  case res of
    Nothing -> return []
    Just (Object _ [] objs) -> subObjects objs
    Just (Object _ iface objs) -> fmap (path:) $ subObjects objs

  where subObjects objs = fmap concat $ mapM (collectObjects client service . getPath) objs  

getPath (Object p _ _) = p

getInterfaces :: Client -> BusName -> ObjectPath -> IO [InterfaceName]
getInterfaces client service path = do
  res <- introspect client service path
  case res of
    Nothing -> return []
    Just (Object _ ifaces _) -> return $ map getIfaceName ifaces

getIfaceName (Interface n _ _ _) = n

data Iface = Iface [Method] [Signal] [Property]

mkIface (Interface _ ms ss ps) = Iface ms ss ps

getMembers :: Client -> BusName -> ObjectPath -> InterfaceName -> IO (Maybe Iface)
getMembers client service path iface = do
  res <- introspect client service path
  case res of 
    Nothing -> return Nothing
    Just (Object _ ifs _) -> do
      return . fmap mkIface $ find (\(Interface n _ _ _) -> n == iface) ifs