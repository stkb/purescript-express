module Node.Express.App
    ( AppM()
    , App()
    , listenHttp, listenHttps, apply
    , use, useExternal, useAt, useOnParam, useOnError
    , getProp, setProp
    , http, get, post, put, delete, all
    ) where

import Prelude hiding (apply)
import Data.Foreign.Class
import Data.Function
import Data.Maybe
import Control.Monad.Eff
import Control.Monad.Eff.Class
import Control.Monad.Eff.Exception
import Control.Monad.Eff.Unsafe
import Node.HTTP (Server ())

import Node.Express.Types
import Node.Express.Internal.App
import Node.Express.Handler


-- | Monad responsible for application related operations (initial setup mostly).
data AppM e a = AppM (Application -> Eff e a)
type App e = AppM (express :: EXPRESS | e) Unit

instance functorAppM :: Functor (AppM e) where
    map f (AppM h) = AppM \app -> liftM1 f $ h app

instance applyAppM :: Apply (AppM e) where
    apply (AppM f) (AppM h) = AppM \app -> do
        res <- h app
        trans <- f app
        return $ trans res

instance applicativeAppM :: Applicative (AppM e) where
    pure x = AppM \_ -> return x

instance bindAppM :: Bind (AppM e) where
    bind (AppM h) f = AppM \app -> do
        res <- h app
        case f res of
             AppM g -> g app

instance monadAppM :: Monad (AppM e)

instance monadEffAppM :: MonadEff eff (AppM eff) where
    liftEff act = AppM \_ -> act


-- | Run application on specified port and execute callback after launch.
-- | HTTP version
listenHttp :: forall e1 e2. App e1 -> Port -> (Event -> Eff e2 Unit) -> ExpressM e1 Server
listenHttp (AppM act) port cb = do
    app <- intlMkApplication
    act app
    intlAppListenHttp app port cb

-- | Run application on specified port and execute callback after launch.
-- | HTTPS version
listenHttps :: forall e1 e2 opts.
    App e1 -> Port -> opts -> (Event -> Eff e2 Unit) -> ExpressM e1 Server
listenHttps (AppM act) port opts cb = do
    app <- intlMkApplication
    act app
    intlAppListenHttps app port opts cb

-- | Apply App actions to existent Express.js application
apply :: forall e. App e -> Application -> ExpressM e Unit
apply (AppM act) app = act app

-- | Use specified middleware handler.
use :: forall e. Handler e -> App e
use middleware = AppM \app ->
    intlAppUse app $ runHandlerM middleware

-- | Use any function as middleware.
-- | Introduced to ease usage of a bunch of external
-- | middleware written for express.js.
-- | See http://expressjs.com/4x/api.html#middleware
useExternal :: forall e. Fn3 Request Response (ExpressM e Unit) (ExpressM e Unit) -> App e
useExternal fn = AppM \app ->
    intlAppUseExternal app fn

-- | Use specified middleware only on requests matching path.
useAt :: forall e. Path -> Handler e -> App e
useAt route middleware = AppM \app ->
    intlAppUseAt app route $ runHandlerM middleware

-- | Process route param with specified handler.
useOnParam :: forall e. String -> (String -> Handler e) -> App e
useOnParam param handler = AppM \app ->
    intlAppUseOnParam app param (runHandlerM <<< handler)

-- | Use error handler. Probably this should be the last middleware to attach.
useOnError :: forall e. (Error -> Handler e) -> App e
useOnError handler = AppM \app ->
    intlAppUseOnError app (runHandlerM <<< handler)


-- | Get application property.
-- | See http://expressjs.com/4x/api.html#app-settings
getProp :: forall e a. (IsForeign a) => String -> AppM (express :: EXPRESS | e) (Maybe a)
getProp name = AppM \app ->
    intlAppGetProp app name

-- | Set application property.
-- | See http://expressjs.com/4x/api.html#app-settings
setProp :: forall e a. (IsForeign a) => String -> a -> App e
setProp name val = AppM \app ->
    intlAppSetProp app name val


-- | Bind specified handler to handle request matching route and method.
http :: forall e r. (RoutePattern r) => Method -> r -> Handler e -> App e
http method route handler = AppM \app ->
    intlAppHttp app (show method) route $ runHandlerM handler

-- | Shortcut for `http GET`.
get :: forall e r. (RoutePattern r) => r -> Handler e -> App e
get = http GET

-- | Shortcut for `http POST`.
post :: forall e r. (RoutePattern r) => r -> Handler e -> App e
post = http POST

-- | Shortcut for `http PUT`.
put :: forall e r. (RoutePattern r) => r -> Handler e -> App e
put = http PUT

-- | Shortcut for `http DELETE`.
delete :: forall e r. (RoutePattern r) => r -> Handler e -> App e
delete = http DELETE

-- | Shortcut for `http ALL` (match on any http method).
all :: forall e r. (RoutePattern r) => r -> Handler e -> App e
all = http ALL
