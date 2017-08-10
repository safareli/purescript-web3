module Network.Ethereum.Web3.Encoding where

import Prelude
import Data.Maybe (Maybe(..))
import Control.Error.Util (hush)
import Data.Array ((:))
import Data.Array (uncons, length) as A
import Data.Foldable (fold, foldMap)
import Data.ByteString (toUTF8, fromUTF8, empty, length) as BS
import Data.Tuple (Tuple(..), fst, snd)
import Type.Proxy (Proxy(..))
import Data.Lens.Index (ix)
import Data.Lens.Setter (over)
import Text.Parsing.Parser (Parser, runParser, fail)


import Network.Ethereum.Web3.Types (Address(..), BigNumber, HexString, getPadLength,
                                    padLeft, toInt, unHex, hexLength)
import Network.Ethereum.Web3.Encoding.Internal (class EncodingType, isDynamic, int256HexBuilder,
                                                int256HexParser, take)
import Network.Ethereum.Web3.Encoding.Bytes (BytesN(..), BytesD(..) , bytesBuilder, bytesDecode, unBytesD, update)
import Network.Ethereum.Web3.Encoding.Size (class KnownSize, sizeVal)

class ABIEncoding a where
  toDataBuilder :: a -> HexString
  fromDataParser :: Parser String a

instance abiEncodingAlgebra :: ABIEncoding BigNumber where
  toDataBuilder = int256HexBuilder
  fromDataParser = int256HexParser

-- | Parse encoded value, droping the leading '0x'
fromData :: forall a . ABIEncoding a => HexString -> Maybe a
fromData = hush <<< flip runParser fromDataParser <<< unHex


fromBool :: Boolean -> BigNumber
fromBool b = if b then one else zero

toBool :: BigNumber -> Boolean
toBool bn = not $ bn == zero

instance abiEncodingBool :: ABIEncoding Boolean where
    toDataBuilder  = int256HexBuilder <<< fromBool
    fromDataParser = toBool <$> int256HexParser

instance abiEncodingInt :: ABIEncoding Int where
    toDataBuilder  = int256HexBuilder
    fromDataParser = toInt <$> int256HexParser

instance abiEncodingAddress :: ABIEncoding Address where
    toDataBuilder (Address addr) = padLeft addr
    fromDataParser = do
      _ <- take 24
      Address <$> take 40

instance abiEncodingBytesN :: KnownSize n => ABIEncoding (BytesN n) where
  toDataBuilder (BytesN bs) = bytesBuilder bs
  fromDataParser = do
    let result = (BytesN BS.empty :: BytesN n)
        len = sizeVal (Proxy :: Proxy n)
        zeroBytes = getPadLength (len * 2)
    raw <- take $ len * 2
    _ <- take $ zeroBytes
    pure <<< update result <<< bytesDecode <<< unHex $ raw

instance abiEncodingBytesD :: ABIEncoding BytesD where
  toDataBuilder (BytesD bytes) =
    int256HexBuilder (BS.length bytes) <> bytesBuilder bytes

  fromDataParser = do
    len <- toInt <$> int256HexParser
    BytesD <<< bytesDecode <<< unHex <$> take (len * 2)

instance abiEncodingString :: ABIEncoding String where
    toDataBuilder = toDataBuilder <<<  BytesD <<< BS.toUTF8
    fromDataParser = BS.fromUTF8 <<< unBytesD <$> fromDataParser

accumulate :: Array Int -> Array Int
accumulate as = go 0 as
  where
    go :: Int -> Array Int -> Array Int
    go accum bs = case A.uncons bs of
      Nothing -> []
      Just ht -> let newAccum = accum + ht.head
                 in newAccum : go newAccum ht.tail

encodeArray :: forall a .
               EncodingType a
            => ABIEncoding a
            => Array a
            -> HexString
encodeArray as =
    if not $ isDynamic (Proxy :: Proxy a)
        then toDataBuilder (A.length as) <> foldMap toDataBuilder as
        else let countEncs = map countEnc as
                 offsets = accumulate <<< over (ix 0) (\x -> x - 32) <<< map fst $ countEncs
                 encodings = map snd countEncs
             in  foldMap toDataBuilder offsets <> fold encodings
  where
    countEnc a = let enc = toDataBuilder a
                 in Tuple (hexLength enc `div` 2) enc

instance abiEncodingArray :: (EncodingType a, ABIEncoding a) => ABIEncoding (Array a) where
    toDataBuilder = encodeArray
    fromDataParser = fail "oops"
