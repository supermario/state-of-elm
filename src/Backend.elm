module Backend exposing (..)

import AdminPage exposing (AdminLoginData)
import AnswerMap exposing (AnswerMap)
import AssocList as Dict
import AssocSet as Set
import DataEntry
import Effect.Command as Command exposing (BackendOnly, Command)
import Effect.Lamdera exposing (ClientId, SessionId)
import Effect.Task
import Effect.Time
import Env
import Form exposing (Form, FormMapping)
import FreeTextAnswerMap
import Lamdera
import List.Nonempty exposing (Nonempty)
import Questions exposing (Question)
import Sha256
import SurveyResults
import Types exposing (..)
import Ui exposing (MultiChoiceWithOther)


app =
    Effect.Lamdera.backend
        Lamdera.broadcast
        Lamdera.sendToFrontend
        { init = init
        , update = update
        , updateFromFrontend = updateFromFrontend
        , subscriptions = \_ -> Effect.Lamdera.onConnect UserConnected
        }


init : ( BackendModel, Command restriction toMsg BackendMsg )
init =
    let
        answerMap : FormMapping
        answerMap =
            { doYouUseElm = ""
            , age = ""
            , functionalProgrammingExperience = ""
            , otherLanguages = AnswerMap.init Questions.otherLanguages
            , newsAndDiscussions = AnswerMap.init Questions.newsAndDiscussions
            , elmResources = AnswerMap.init Questions.elmResources
            , elmInitialInterest = FreeTextAnswerMap.init
            , countryLivingIn = ""
            , applicationDomains = AnswerMap.init Questions.applicationDomains
            , doYouUseElmAtWork = ""
            , howLargeIsTheCompany = ""
            , whatLanguageDoYouUseForBackend = AnswerMap.init Questions.whatLanguageDoYouUseForBackend
            , howLong = ""
            , elmVersion = AnswerMap.init Questions.elmVersion
            , doYouUseElmFormat = ""
            , stylingTools = AnswerMap.init Questions.stylingTools
            , buildTools = AnswerMap.init Questions.buildTools
            , frameworks = AnswerMap.init Questions.frameworks
            , editors = AnswerMap.init Questions.editors
            , doYouUseElmReview = ""
            , whichElmReviewRulesDoYouUse = AnswerMap.init Questions.whichElmReviewRulesDoYouUse
            , testTools = AnswerMap.init Questions.testTools
            , testsWrittenFor = AnswerMap.init Questions.testsWrittenFor
            , biggestPainPoint = FreeTextAnswerMap.init
            , whatDoYouLikeMost = FreeTextAnswerMap.init
            }
    in
    ( { forms = Dict.empty
      , answerMap = answerMap
      , adminLogin = Set.empty
      }
    , Command.none
    )


getAdminData : BackendModel -> AdminLoginData
getAdminData model =
    { forms = Dict.values model.forms, formMapping = model.answerMap }


update : BackendMsg -> BackendModel -> ( BackendModel, Command BackendOnly ToFrontend BackendMsg )
update msg model =
    case msg of
        UserConnected sessionId clientId ->
            ( model
            , if isAdmin sessionId model then
                LoadAdmin (getAdminData model) |> Effect.Lamdera.sendToFrontend clientId

              else
                Effect.Time.now |> Effect.Task.perform (GotTimeWithLoadFormData sessionId clientId)
            )

        GotTimeWithLoadFormData sessionId clientId time ->
            ( model, loadFormData sessionId time model |> LoadForm |> Effect.Lamdera.sendToFrontend clientId )

        GotTimeWithUpdate sessionId clientId toBackend time ->
            updateFromFrontendWithTime time sessionId clientId toBackend model


loadFormData : SessionId -> Effect.Time.Posix -> BackendModel -> LoadFormStatus
loadFormData sessionId time model =
    case Types.surveyStatus of
        SurveyOpen ->
            if Env.surveyIsOpen time then
                case Dict.get sessionId model.forms of
                    Just value ->
                        case value.submitTime of
                            Just _ ->
                                FormSubmitted

                            Nothing ->
                                FormAutoSaved value.form

                    Nothing ->
                        NoFormFound

            else
                AwaitingResultsData

        SurveyFinished ->
            let
                forms : List Form
                forms =
                    Dict.values model.forms
                        |> List.filterMap
                            (\{ form, submitTime } ->
                                case submitTime of
                                    Just _ ->
                                        Just form

                                    Nothing ->
                                        Nothing
                            )

                segmentWithOther :
                    (Form -> MultiChoiceWithOther a)
                    -> (FormMapping -> AnswerMap a)
                    -> Question a
                    -> SurveyResults.DataEntryWithOtherSegments a
                segmentWithOther formField answerMapField question =
                    { users =
                        List.filterMap
                            (\form ->
                                if Form.doesNotUseElm form then
                                    Nothing

                                else
                                    Just (formField form)
                            )
                            forms
                            |> DataEntry.fromMultiChoiceWithOther question (answerMapField model.answerMap)
                    , potentialUsers =
                        List.filterMap
                            (\form ->
                                if Form.doesNotUseElm form && not (Form.notInterestedInElm form) then
                                    Just (formField form)

                                else
                                    Nothing
                            )
                            forms
                            |> DataEntry.fromMultiChoiceWithOther question (answerMapField model.answerMap)
                    }

                segment : (Form -> Maybe a) -> (FormMapping -> String) -> Question a -> SurveyResults.DataEntrySegments a
                segment formField answerMapField question =
                    { users =
                        List.filterMap
                            (\form ->
                                if Form.doesNotUseElm form then
                                    Nothing

                                else
                                    formField form
                            )
                            forms
                            |> DataEntry.fromForms (answerMapField model.answerMap) question.choices
                    , potentialUsers =
                        List.filterMap
                            (\form ->
                                if Form.doesNotUseElm form && not (Form.notInterestedInElm form) then
                                    formField form

                                else
                                    Nothing
                            )
                            forms
                            |> DataEntry.fromForms (answerMapField model.answerMap) question.choices
                    }

                segmentFreeText formField answerMapField =
                    { users =
                        List.filterMap
                            (\form ->
                                if Form.doesNotUseElm form then
                                    Nothing

                                else
                                    Just (formField form)
                            )
                            forms
                            |> DataEntry.fromFreeText (answerMapField model.answerMap)
                    , potentialUsers =
                        List.filterMap
                            (\form ->
                                if Form.doesNotUseElm form && not (Form.notInterestedInElm form) then
                                    Just (formField form)

                                else
                                    Nothing
                            )
                            forms
                            |> DataEntry.fromFreeText (answerMapField model.answerMap)
                    }
            in
            { totalParticipants = List.length forms
            , doYouUseElm =
                List.concatMap (.doYouUseElm >> Set.toList) forms
                    |> DataEntry.fromForms model.answerMap.doYouUseElm Questions.doYouUseElm.choices
            , age = segment .age .age Questions.age
            , functionalProgrammingExperience =
                segment .functionalProgrammingExperience .functionalProgrammingExperience Questions.experienceLevel
            , otherLanguages = segmentWithOther .otherLanguages .otherLanguages Questions.otherLanguages
            , newsAndDiscussions = segmentWithOther .newsAndDiscussions .newsAndDiscussions Questions.newsAndDiscussions
            , elmResources = segmentWithOther .elmResources .elmResources Questions.elmResources
            , elmInitialInterest = segmentFreeText .elmInitialInterest .elmInitialInterest
            , countryLivingIn = segment .countryLivingIn .countryLivingIn Questions.countryLivingIn
            , doYouUseElmAtWork =
                List.filterMap .doYouUseElmAtWork forms
                    |> DataEntry.fromForms model.answerMap.doYouUseElmAtWork Questions.doYouUseElmAtWork.choices
            , applicationDomains =
                List.map .applicationDomains forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.applicationDomains model.answerMap.applicationDomains
            , howLargeIsTheCompany =
                List.filterMap .howLargeIsTheCompany forms
                    |> DataEntry.fromForms model.answerMap.howLargeIsTheCompany Questions.howLargeIsTheCompany.choices
            , whatLanguageDoYouUseForBackend =
                List.map .whatLanguageDoYouUseForBackend forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.whatLanguageDoYouUseForBackend model.answerMap.whatLanguageDoYouUseForBackend
            , howLong = List.filterMap .howLong forms |> DataEntry.fromForms model.answerMap.howLong Questions.howLong.choices
            , elmVersion =
                List.map .elmVersion forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.elmVersion model.answerMap.elmVersion
            , doYouUseElmFormat =
                List.filterMap .doYouUseElmFormat forms
                    |> DataEntry.fromForms model.answerMap.doYouUseElmFormat Questions.doYouUseElmFormat.choices
            , stylingTools =
                List.map .stylingTools forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.stylingTools model.answerMap.stylingTools
            , buildTools =
                List.map .buildTools forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.buildTools model.answerMap.buildTools
            , frameworks =
                List.map .frameworks forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.frameworks model.answerMap.frameworks
            , editors =
                List.map .editors forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.editors model.answerMap.editors
            , doYouUseElmReview =
                List.filterMap .doYouUseElmReview forms
                    |> DataEntry.fromForms model.answerMap.doYouUseElmReview Questions.doYouUseElmReview.choices
            , whichElmReviewRulesDoYouUse =
                List.map .whichElmReviewRulesDoYouUse forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.whichElmReviewRulesDoYouUse model.answerMap.whichElmReviewRulesDoYouUse
            , testTools =
                List.map .testTools forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.testTools model.answerMap.testTools
            , testsWrittenFor =
                List.map .testsWrittenFor forms
                    |> DataEntry.fromMultiChoiceWithOther Questions.testsWrittenFor model.answerMap.testsWrittenFor
            , biggestPainPoint =
                List.map .biggestPainPoint forms
                    |> DataEntry.fromFreeText model.answerMap.biggestPainPoint
            , whatDoYouLikeMost =
                List.map .whatDoYouLikeMost forms
                    |> DataEntry.fromFreeText model.answerMap.whatDoYouLikeMost
            }
                |> SurveyResults


updateFromFrontend : SessionId -> ClientId -> ToBackend -> BackendModel -> ( BackendModel, Command restriction toMsg BackendMsg )
updateFromFrontend sessionId clientId msg model =
    ( model, Effect.Time.now |> Effect.Task.perform (GotTimeWithUpdate sessionId clientId msg) )


updateFromFrontendWithTime : Effect.Time.Posix -> SessionId -> ClientId -> ToBackend -> BackendModel -> ( BackendModel, Command BackendOnly ToFrontend BackendMsg )
updateFromFrontendWithTime time sessionId clientId msg model =
    case msg of
        AutoSaveForm form ->
            case Types.surveyStatus of
                SurveyOpen ->
                    ( if Env.surveyIsOpen time then
                        { model
                            | forms =
                                Dict.update
                                    sessionId
                                    (\maybeValue ->
                                        case maybeValue of
                                            Just value ->
                                                case value.submitTime of
                                                    Just _ ->
                                                        maybeValue

                                                    Nothing ->
                                                        Just { value | form = form }

                                            Nothing ->
                                                Just { form = form, submitTime = Nothing }
                                    )
                                    model.forms
                        }

                      else
                        model
                    , Command.none
                    )

                SurveyFinished ->
                    ( model, Command.none )

        SubmitForm form ->
            case Types.surveyStatus of
                SurveyOpen ->
                    if Env.surveyIsOpen time then
                        ( { model
                            | forms =
                                Dict.update
                                    sessionId
                                    (\maybeValue ->
                                        case maybeValue of
                                            Just value ->
                                                case value.submitTime of
                                                    Just _ ->
                                                        maybeValue

                                                    Nothing ->
                                                        Just { value | form = form, submitTime = Just time }

                                            Nothing ->
                                                Just { form = form, submitTime = Just time }
                                    )
                                    model.forms
                          }
                        , Effect.Lamdera.sendToFrontend clientId SubmitConfirmed
                        )

                    else
                        ( model, Command.none )

                SurveyFinished ->
                    ( model, Command.none )

        AdminLoginRequest password ->
            if Env.adminPasswordHash == Sha256.sha256 password then
                ( { model | adminLogin = Set.insert sessionId model.adminLogin }
                , getAdminData model |> Ok |> AdminLoginResponse |> Effect.Lamdera.sendToFrontend clientId
                )

            else
                ( model, Err () |> AdminLoginResponse |> Effect.Lamdera.sendToFrontend clientId )

        AdminToBackend (AdminPage.ReplaceFormsRequest forms) ->
            ( if not Env.isProduction && isAdmin sessionId model then
                { model
                    | forms =
                        List.indexedMap
                            (\index form ->
                                ( Char.fromCode index |> String.fromChar |> Effect.Lamdera.sessionIdFromString
                                , { form = form, submitTime = Just (Effect.Time.millisToPosix 0) }
                                )
                            )
                            forms
                            |> Dict.fromList
                }

              else
                model
            , Command.none
            )

        AdminToBackend AdminPage.LogOutRequest ->
            if isAdmin sessionId model then
                ( { model | adminLogin = Set.remove sessionId model.adminLogin }
                , loadFormData sessionId time model |> LogOutResponse |> Effect.Lamdera.sendToFrontend clientId
                )

            else
                ( model, Command.none )

        AdminToBackend (AdminPage.EditFormMappingRequest edit) ->
            if isAdmin sessionId model then
                ( { model | answerMap = AdminPage.networkUpdate edit model.answerMap }
                , Set.toList model.adminLogin
                    |> List.map
                        (\sessionId_ ->
                            AdminToFrontend (AdminPage.EditFormMappingResponse edit)
                                |> Effect.Lamdera.sendToFrontends sessionId_
                        )
                    |> Command.batch
                )

            else
                ( model, Command.none )


isAdmin : SessionId -> BackendModel -> Bool
isAdmin sessionId model =
    Set.member sessionId model.adminLogin
