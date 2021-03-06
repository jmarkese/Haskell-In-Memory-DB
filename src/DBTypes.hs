{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ExistentialQuantification #-} 
{-# LANGUAGE RankNTypes #-}

{- Exporting all types, constructors, and accessors -}

module DBTypes (Tablename(..)
  , ErrString(..)
  , Database(..)
  , Fieldname(..)
  , Table(..)
  , Column(..)
  , Element(..)
  , TransactionID(..)
  , RowHash(..)
  , LogOperation(..)
  , Row(..)
  , Log
  , ActiveTransactions) where


import Data.Typeable 
import Control.Concurrent.STM
import Test.QuickCheck
import Data.ByteString (ByteString)
import Data.Char
import Data.List (isPrefixOf, stripPrefix)
import Data.Maybe
import Data.Map.Lazy (Map)
import Data.Set (Set)

import System.IO.Unsafe


newtype Tablename = Tablename String deriving(Ord, Eq, Show, Read)
newtype ErrString = ErrString String deriving(Show)

data Database = Database { database :: Map Tablename (TVar Table) }
data Fieldname = Fieldname String deriving(Ord, Eq, Show, Read)

instance Arbitrary Fieldname where
  arbitrary = fmap Fieldname (arbitrary :: Gen String)

instance Arbitrary Tablename where
  arbitrary = fmap Tablename (arbitrary :: Gen String)

data Table = Table { rowCounter :: Int 
                   , primaryKey :: Maybe Fieldname 
                   , table :: Map Fieldname Column}

data Column = Column { default_val :: Maybe Element
                     , col_type :: TypeRep
                     , column :: TVar(Map RowHash (TVar Element))
                     } -- first element is default value

data Element = forall a. (Show a, Ord a, Eq a, Read a, Typeable a) => Element (Maybe a) -- Nothing here means that it's null

instance Show Element where
  show (Element x) | typeOf x == typeOf (undefined::Maybe Int)        = "Int" ++ show x
                   | typeOf x == typeOf (undefined::Maybe Double)     = "Double" ++ show x
                   | typeOf x == typeOf (undefined::Maybe ByteString) = "ByteString" ++ show x


instance Read Element where
  readsPrec _ str' = let help str | isPrefixOf "Int" str        = map (\(a,b) -> (Element a, b)) $ (readsPrec 0 :: ReadS (Maybe Int)) $ fromJust $ stripPrefix "Int" str
                                  | isPrefixOf "Double" str     = map (\(a,b) -> (Element a, b)) $ (readsPrec 0 :: ReadS (Maybe Double)) $ fromJust $ stripPrefix "Double" str
                                  | isPrefixOf "ByteString" str = map (\(a,b) -> (Element a, b)) $ (readsPrec 0 :: ReadS (Maybe ByteString)) $ fromJust $ stripPrefix "ByteString" str
                      in help $ dropWhile isSpace str'

instance Eq Element where
  (Element mx) == (Element my) = case cast mx of Just typed_mx -> typed_mx == my
                                                 Nothing       -> False

data TransactionID = TransactionID { clientName :: String 
                                   , transactionNum :: Int 
                                   } deriving(Eq, Ord, Show, Read)-- clientname, transaction number
 
data Row = Row {getField :: Fieldname -> STM(Maybe Element)}

newtype RowHash = RowHash Int deriving(Show, Read, Eq, Ord) 
data LogOperation = Start TransactionID
                  | Insert TransactionID (Tablename, RowHash) [(Fieldname, Element)]
                  | Delete TransactionID (Tablename, RowHash) [(Fieldname, Element)]
                  | Update TransactionID (Tablename, RowHash) [(Fieldname, Element, Element)] -- last two are old val, new val
                  | Commit TransactionID  
                  | StartCheckpoint [TransactionID]   
                  | EndCheckpoint
                  | DropTable TransactionID Tablename 
                  | CreateTable TransactionID Tablename
                  | AddField TransactionID Tablename Fieldname
                  | DropField TransactionID Tablename Fieldname
                  | SetPrimaryKey TransactionID (Maybe Fieldname) (Maybe Fieldname) Tablename -- old field, new field
                  deriving (Show, Read) 

type Log = TChan LogOperation
type ActiveTransactions = Set TransactionID
