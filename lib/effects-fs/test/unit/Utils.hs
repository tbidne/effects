module Utils (tests) where

import Control.Monad (void)
import Data.Either (isRight)
import Effects.FileSystem.Utils (OsPath)
import Effects.FileSystem.Utils qualified as Utils
import Hedgehog
  ( Gen,
    PropertyT,
    annotate,
    annotateShow,
    evalNF,
    forAll,
    (===),
  )
import Hedgehog qualified as H
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.OsPath qualified as OsPath
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Utils"
    [ testEncodeLenientTotal,
      testEncodeLenientEqualsEncode,
      testEncodeValidLenientTotal,
      testEncodeValidLenientEqualsEncode,
      testDecodeLenientTotal,
      testDecodeLenientEqualsDecode
    ]

testEncodeLenientTotal :: TestTree
testEncodeLenientTotal = testPropertyNamed desc "testEncodeLenientTotal" $ do
  H.property $ do
    fp <- forAll genSketchyFilePath

    let encoded = Utils.encodeFpToOsLenient fp

    void $ evalNF encoded
  where
    desc = "encodeFpToOsLenient is total"

testEncodeLenientEqualsEncode :: TestTree
testEncodeLenientEqualsEncode = testPropertyNamed desc "testEncodeLenientEqualsEncode" $ do
  H.property $ do
    filePath <- forAll genFilePath

    let eEncoded = Utils.encodeFpToOs filePath
        encodedLenient = Utils.encodeFpToOsLenient filePath
        encodeSuccess = isRight eEncoded

    annotateShow encodedLenient

    compareWithCoverage encodeSuccess eEncoded encodedLenient
  where
    desc = "encodeFpToOs == encodeOsToFpLenient for good paths"

testEncodeValidLenientTotal :: TestTree
testEncodeValidLenientTotal = testPropertyNamed desc "testEncodeValidLenientTotal" $ do
  H.property $ do
    fp <- forAll genSketchyFilePath

    let encoded = Utils.encodeFpToValidOsLenient fp

    void $ evalNF encoded
  where
    desc = "encodeFpToValidOsLenient is total"

testEncodeValidLenientEqualsEncode :: TestTree
testEncodeValidLenientEqualsEncode = testPropertyNamed desc "testEncodeValidLenientEqualsEncode" $ do
  H.property $ do
    filePath <- forAll genFilePath

    let eEncoded = Utils.encodeFpToValidOs filePath
        encodedLenient = Utils.encodeFpToValidOsLenient filePath
        encodeSuccess = isRight eEncoded

    annotateShow encodedLenient

    compareWithCoverage encodeSuccess eEncoded encodedLenient
  where
    desc = "encodeFpToValidOs == encodeFpToValidOsLenient for good paths"

testDecodeLenientTotal :: TestTree
testDecodeLenientTotal = testPropertyNamed desc "testDecodeLenientTotal" $ do
  H.property $ do
    osPath <- forAll genSketchyOsPath

    let decoded = Utils.decodeOsToFpLenient osPath

    void $ evalNF decoded
  where
    desc = "decodeOsToFpLenient is total"

testDecodeLenientEqualsDecode :: TestTree
testDecodeLenientEqualsDecode = testPropertyNamed desc "testDecodeLenientEqualsDecode" $ do
  H.property $ do
    osPath <- forAll genValidOsPath

    let eDecoded = Utils.decodeOsToFp osPath
        decodedLenient = Utils.decodeOsToFpLenient osPath
        decodeSuccess = isRight eDecoded

    annotate decodedLenient

    compareWithCoverage decodeSuccess eDecoded decodedLenient
  where
    desc = "decodeOsToFp == decodeOsToFpLenient for good paths"

-- NOTE: [Generating good paths]
--
-- We want to test "when paths are good ==> encode <=> encodeLenient",
-- thus we want encoding to succeed. This is hard to gurantee, however,
-- so in the case of an encode failure, we simply skip the test.
--
-- We want to ensure we are actually testing the right path most of
-- the time, hence the coverage check.
--
-- The CoverPercentage is very high because in general there are very few
-- generated paths that do not encode successfully. It isn't zero, though,
-- so we cannot assume it always succeeds. We include the coverage check to
-- ensure we are actually testing what we want most of the time.
--
-- We have tested that this actually make sense i.e. in a run with 100,000
-- tests, only 3 failed, so there are in fact __some__ failures, but very few.
--
-- Note that hedghog's coverage checker performs rounding. In particular,
-- 99.5+ will round to 100.
compareWithCoverage ::
  ( Eq a,
    Show a
  ) =>
  Bool ->
  Either e a ->
  a ->
  PropertyT IO ()
compareWithCoverage isSuccess eResult resultLenient = do
  H.cover 99 "Generation succeeded" isSuccess
  case eResult of
    Left _ -> H.label "Generated bad path"
    Right result -> do
      H.label "Generated good path"
      result === resultLenient

-- | The idea is, generate a possibly invalid OsPath s.t. generation is total
-- but decoding might fail. Turns out this works i.e. if we replace
-- decodeOsToFpLenient with unsafeDecodeOsToFp, then the test fails
-- (which is what we want, since we want to test that lenient is actually
-- doing something).
genSketchyOsPath :: Gen OsPath
genSketchyOsPath = do
  str <- genSketchyFilePath
  let osCharList = OsPath.unsafeFromChar <$> str
  pure $ OsPath.pack osCharList

genSketchyFilePath :: Gen FilePath
genSketchyFilePath = genSomeFilePath 0 Gen.unicodeAll

genValidOsPath :: Gen OsPath
genValidOsPath = Utils.unsafeEncodeFpToValidOs <$> genFilePath

genFilePath :: Gen FilePath
genFilePath = genSomeFilePath 1 g
  where
    g = Gen.filter (/= '\NUL') Gen.unicode

genSomeFilePath :: Int -> Gen Char -> Gen FilePath
genSomeFilePath start = Gen.string (Range.linearFrom start start 50)
