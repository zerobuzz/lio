{-# OPTIONS_GHC -fno-warn-orphans #-}

import Control.Applicative
import Criterion
import qualified Criterion.Main as Cr
import qualified Data.ByteString.Char8 as S
import Data.Hashable
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Word
import System.Random
import qualified Test.Framework as T
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck hiding ((.&.))
import Test.QuickCheck.Gen
import Text.Printf

import LIO.Label
import LIO.Privs
import qualified LIO.DCLabel as O
import qualified LIO.DCLabel.Core as O
import qualified LIO.DCLabel.Fast as F

instance (Ord a, Arbitrary a) => Arbitrary (Set a) where
  arbitrary = Set.fromList <$> arbitrary

newtype PName = PName { unPName :: S.ByteString } deriving Show
instance Arbitrary PName where
  arbitrary = PName <$> S.pack <$> printf "p%02d" <$> choose (1::Int,32)

pGen :: Gen [[S.ByteString]]
pGen = map (map unPName) <$> arbitrary

newtype PSS = PSS { unPSS :: [[S.ByteString]] } deriving Show
instance Arbitrary PSS where
  arbitrary = PSS <$> pGen

mkCNF :: [[S.ByteString]] -> F.CNF
mkCNF = F.cFromList . map (F.dFromList . map F.principalBS)

mkComponent :: [[S.ByteString]] -> O.Component
mkComponent [] = O.dcTrue
mkComponent ss | any null ss = O.DCFalse
mkComponent ss = O.dcReduce $ O.DCFormula $ Set.fromList $ map mkClause ss
  where mkClause = O.Clause . Set.fromList . map O.Principal

oldNewSameProp :: PSS -> Bool
oldNewSameProp (PSS ss) = show (mkCNF ss) == show (mkComponent ss)

oldNewSameAnd :: PSS -> PSS -> Bool
oldNewSameAnd (PSS ps1) (PSS ps2) =
  show (mkComponent ps1 O./\ mkComponent ps2) == show (mkCNF ps1 F./\ mkCNF ps2)

oldNewSameOr :: PSS -> PSS -> Bool
oldNewSameOr (PSS ps1) (PSS ps2) =
  show (mkComponent ps1 O.\/ mkComponent ps2) == show (mkCNF ps1 F.\/ mkCNF ps2)

oldNewSameDowngrade :: PSS -> PSS -> Bool
oldNewSameDowngrade (PSS p) (PSS l) =
  show (downgradePrivDesc (mkComponent p) (mkComponent l O.%% True))
  == show (downgradePrivDesc (mkCNF p) (mkCNF l F.%% True))

oldNewSame :: IO ()
oldNewSame = T.defaultMain [
    testProperty "oldNewSameProp" oldNewSameProp
  , testProperty "oldNewSameAnd" oldNewSameAnd
  , testProperty "oldNewSameOr" oldNewSameOr
  , testProperty "oldNewSameDowngrade" oldNewSameDowngrade
  ]


sssmall = unGen pGen (mkStdGen 2) 10
sssmall1 = unGen pGen (mkStdGen 4) 10
ssbig = unGen pGen (mkStdGen 12312) 100

fbig = mkCNF ssbig
fsmall = mkCNF sssmall
fsmall1 = mkCNF sssmall1

obig = mkComponent ssbig
osmall = mkComponent sssmall
osmall1 = mkComponent sssmall1

sanity :: Bool
sanity = foldl1 (&&) [
    show fbig == show obig
  , show (mkComponent sssmall1) == show (mkCNF sssmall1)
  , show (fbig F./\ fsmall) == show (obig O./\ osmall)
  , show (fbig F.\/ fsmall) == show (obig O.\/ osmall)
  , show (downgradePrivDesc fsmall (fbig F.%% True))
    == show (downgradePrivDesc osmall (obig O.%% True))
  ] 


main = do
  True <- return sanity
  Cr.defaultMain [
      bench "mkCNF" $ whnf mkCNF ssbig
    , bench "mkComponent" $ whnf mkComponent ssbig
    , bench "mkCNF small" $ whnf mkCNF sssmall1
    , bench "mkComponent small" $ whnf mkComponent sssmall1
    , bench "F./\\" $ whnf (fbig F./\) fsmall
    , bench "O./\\" $ whnf (obig O./\) osmall
    , bench "F.\\/" $ whnf (fbig F.\/) fsmall
    , bench "O.\\/" $ whnf (obig O.\/) osmall
    , bench "F.downgradePrivDesc" $
      whnf (downgradePrivDesc fsmall) (fbig F.%% True)
    , bench "O.downgradePrivDesc" $
      whnf (downgradePrivDesc osmall) (obig O.%% True)
    , bench "F.lub" $ whnf (lub (fsmall F.%% fsmall)) (fsmall1 F.%% fsmall1)
    , bench "O.lub" $ whnf (lub (osmall O.%% osmall)) (osmall1 O.%% osmall1)
    ]

--[bench "\\/" $ whnf (c0 \/) c1]

-- Local Variables:
-- haskell-program-name: "ghci -i.."
-- End:
