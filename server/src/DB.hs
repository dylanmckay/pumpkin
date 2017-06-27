{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

module DB
  ( loadEnvironments
  , loadBugs
  , BugSearch(..)
  , loadBugDetails
  , loadBugOccurrences
  , closeBug
  , createIssue
  , deleteIssue
  , createOccurrence
  , withConnection
  , Connection
  ) where

import Control.Exception (bracket)
import Control.Monad (void)
import Data.Aeson (Value)
import Data.Maybe (listToMaybe)
import Data.Monoid ((<>))
import Data.Text (Text)
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.FromField
import Database.PostgreSQL.Simple.ToField
import Network.URI (URI)
import qualified Network.URI as URI
import Types

withConnection :: (Connection -> IO a) -> IO a
withConnection = bracket (connectPostgreSQL "") close

instance FromRow Environment

loadEnvironments :: IO [Environment]
loadEnvironments =
  withConnection $
  \conn ->
     query_
       conn
       " SELECT id FROM \
      \   (SELECT e.*, last_occurred_at FROM environments e \
      \      JOIN (SELECT environment_id, MAX(occurred_at) AS last_occurred_at \
      \            FROM occurrences GROUP BY environment_id) AS l \
      \        ON l.environment_id = e.id \
      \     ORDER BY last_occurred_at DESC) AS envs"

data BugSearch = BugSearch
  { bsEnvIDs :: [EnvironmentID]
  , bsClosed :: Bool
  , bsSearch :: Maybe Text
  , bsLimit :: Int
  , bsStart :: Maybe Int
  } deriving (Show)

instance FromRow Issue

instance FromRow Bug

bugListSelect :: Query
bugListSelect =
  " SELECT b.id \
  \      , message \
  \      , o.occurred_at AS first_occurred_at \
  \      , last_occurred_at \
  \      , (SELECT COUNT(1) FROM occurrences WHERE bug_id = b.id) AS occurrence_count \
  \      , e.created_at AS closed_at \
  \      , o.data \
  \ FROM bug_with_latest_details b \
  \ JOIN occurrences o ON o.id = b.primary_occurrence_id \
  \ LEFT OUTER JOIN events e ON latest_event_id = e.id AND e.name = 'closed'"

loadBugs :: BugSearch -> IO [BugWithIssues]
loadBugs search =
  withConnection $
  \conn -> do
    bugs <-
      query
        conn
        ("WITH bug_list AS (" <> bugListSelect <> ") " <>
         "SELECT id, message, first_occurred_at, \
         \       last_occurred_at, occurrence_count, closed_at \
         \  FROM bug_list \
         \ WHERE (closed_at IS NULL OR ?) \
         \   AND (? IS NULL \
         \        OR last_occurred_at <= \
         \           (SELECT last_occurred_at FROM bug_with_latest_details WHERE id = ?)) \
         \   AND EXISTS (SELECT 1 FROM occurrences \
         \                WHERE bug_id = bug_list.id \
         \                  AND environment_id IN ? \
         \                  AND (? IS NULL OR ? = '' OR message @@ ?)) \
         \ ORDER BY last_occurred_at DESC LIMIT ?")
        ( bsClosed search
        , bsStart search
        , bsStart search
        , In (bsEnvIDs search)
        , bsSearch search
        , bsSearch search
        , bsSearch search
        , bsLimit search)
    issues <- loadIssuesByBugID conn (bugID <$> bugs)
    return $
      (\bug ->
          BugWithIssues
            bug
            [ i
            | i <- issues
            , issueBugID i == bugID bug ]) <$>
      bugs

loadIssuesByBugID :: Connection -> [BugID] -> IO [Issue]
loadIssuesByBugID conn ids =
  query
    conn
    "SELECT id, bug_id, url FROM issues WHERE bug_id IN ?"
    (Only $ In ids)

loadBugDetails :: BugID -> IO (Maybe BugDetails)
loadBugDetails bug =
  withConnection $
  \conn -> do
    bugs :: [Bug :. Only Value] <-
      query
        conn
        ("WITH bug_list AS (" <> bugListSelect <>
         ") SELECT * FROM bug_list WHERE id = ?")
        (Only bug)
    case listToMaybe bugs of
      Just (bug_ :. Only data_) -> do
        issues <- loadIssuesByBugID conn [bugID bug_]
        return $ Just (BugDetails bug_ issues data_)
      _ -> return Nothing

instance FromRow Occurrence

loadBugOccurrences :: BugID -> Int -> IO [Occurrence]
loadBugOccurrences bug limit =
  withConnection $
  \conn ->
     query
       conn
       "SELECT id, message, occurred_at, data, environment_id, bug_id FROM occurrences WHERE bug_id = ? LIMIT ?"
       (bug, limit)

closeBug :: BugID -> IO ()
closeBug bug =
  withConnection $
  \conn ->
     void $
     execute
       conn
       " INSERT INTO events (bug_id, name, created_at, updated_at) \
      \ SELECT id, 'closed', NOW(), NOW() FROM bugs WHERE id = ?"
       (Only bug)

instance FromField URI where
  fromField f mdata =
    fromField f mdata >>=
    \s ->
       case URI.parseURI s of
         Just uri -> return uri
         _ -> returnError ConversionFailed f ("Invalid URI: " <> s)

instance ToField URI where
  toField u = toField $ URI.uriToString id u ""

createIssue :: BugID -> URI -> IO ()
createIssue bug url =
  withConnection $
  \conn ->
     void $
     execute
       conn
       " INSERT INTO issues (bug_id, url, created_at, updated_at) \
      \ SELECT ?, ?, NOW(), NOW() FROM bugs WHERE id = ?"
       (bug, url, bug)

deleteIssue :: BugID -> IssueID -> IO ()
deleteIssue bug issue =
  withConnection $
  \conn ->
     void $
     execute conn " DELETE FROM issues WHERE bug_id = ? AND id = ?" (bug, issue)

createOccurrence :: NewOccurrence -> IO ()
createOccurrence (NewOccurrence env message data_ occurred_at) =
  void $
  withConnection $
  \conn ->
     withTransaction conn $
     do void $
          execute
            conn
            "INSERT INTO environments (id, created_at, updated_at) SELECT ?, NOW(), NOW() WHERE NOT EXISTS (SELECT 1 FROM environments WHERE id = ?)"
            (env, env)
        void $
          execute
            conn
            " INSERT INTO occurrences \
          \  (environment_id, message, data, occurred_at, created_at, updated_at) \
          \ VALUES ?, ?, ?, ?, NOW(), NOW()"
            (env, message, data_, occurred_at)
