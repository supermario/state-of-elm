module AnswerMap exposing
    ( AnswerMap
    , Hotkey
    , OtherAnswer
    , addGroup
    , allGroups
    , fromFreeText
    , fromMultiChoiceWithOther
    , hotkey
    , hotkeyToIndex
    , hotkeyToString
    , indexToHotkey
    , otherAnswer
    , otherAnswerMapsTo
    , removeGroup
    , renameGroup
    , toggleMapping
    , updateOtherAnswer
    )

import AssocSet as Set exposing (Set)
import List.Extra as List
import List.Nonempty exposing (Nonempty)
import Questions exposing (Question)


type AnswerMap
    = AnswerMap
        { otherMapping : List { groupName : String, otherAnswers : Set OtherAnswer }
        , existingMapping : List (Set OtherAnswer)
        }


type OtherAnswer
    = OtherAnswer String


otherAnswer : String -> OtherAnswer
otherAnswer =
    String.trim >> String.toLower >> OtherAnswer


fromMultiChoiceWithOther : Question a -> AnswerMap
fromMultiChoiceWithOther question =
    { otherMapping = []
    , existingMapping =
        (List.Nonempty.length question.choices - 1)
            |> List.range 0
            |> List.map (\_ -> Set.empty)
    }
        |> AnswerMap


fromFreeText : AnswerMap
fromFreeText =
    { otherMapping = []
    , existingMapping = []
    }
        |> AnswerMap


allGroups : List String -> AnswerMap -> List { hotkey : Hotkey, editable : Bool, groupName : String }
allGroups existingChoices (AnswerMap formMapData) =
    let
        existingChoicesCount =
            List.length existingChoices
    in
    List.indexedMap
        (\index choice ->
            { hotkey = indexToHotkey index
            , groupName = choice
            , editable = False
            }
        )
        existingChoices
        ++ List.indexedMap
            (\index other ->
                { hotkey = indexToHotkey (index + existingChoicesCount)
                , groupName = other.groupName
                , editable = True
                }
            )
            formMapData.otherMapping


otherAnswerMapsTo : OtherAnswer -> AnswerMap -> List Hotkey
otherAnswerMapsTo otherAnswer_ (AnswerMap formMapData) =
    let
        existingCount =
            List.length formMapData.existingMapping
    in
    List.filterMap
        (\( index, set ) ->
            if Set.member otherAnswer_ set then
                indexToHotkey index |> Just

            else
                Nothing
        )
        (List.indexedMap Tuple.pair formMapData.existingMapping)
        ++ List.filterMap
            (\( index, { otherAnswers } ) ->
                if Set.member otherAnswer_ otherAnswers then
                    indexToHotkey (index + existingCount) |> Just

                else
                    Nothing
            )
            (List.indexedMap Tuple.pair formMapData.otherMapping)


updateOtherAnswer : List Hotkey -> OtherAnswer -> AnswerMap -> AnswerMap
updateOtherAnswer hotkeys otherAnswer_ (AnswerMap formMapData) =
    let
        indices : Set Int
        indices =
            List.filterMap hotkeyToIndex hotkeys |> Set.fromList

        offset =
            List.length formMapData.existingMapping
    in
    { otherMapping =
        List.indexedMap
            (\index a ->
                if Set.member (index + offset) indices then
                    { a | otherAnswers = Set.insert otherAnswer_ a.otherAnswers }

                else
                    { a | otherAnswers = Set.remove otherAnswer_ a.otherAnswers }
            )
            formMapData.otherMapping
    , existingMapping =
        List.indexedMap
            (\index set ->
                if Set.member index indices then
                    Set.insert otherAnswer_ set

                else
                    Set.remove otherAnswer_ set
            )
            formMapData.existingMapping
    }
        |> AnswerMap


type Hotkey
    = Hotkey Char


hotkey : Char -> Hotkey
hotkey =
    Hotkey


indexToHotkey : Int -> Hotkey
indexToHotkey index =
    List.getAt index hotkeyChars |> Maybe.withDefault '9' |> hotkey


hotkeyToIndex : Hotkey -> Maybe Int
hotkeyToIndex (Hotkey char) =
    List.elemIndex char hotkeyChars


hotkeyToString : Hotkey -> String
hotkeyToString (Hotkey char) =
    String.fromChar char


hotkeyChars : List Char
hotkeyChars =
    [ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' ]


renameGroup : Hotkey -> String -> AnswerMap -> AnswerMap
renameGroup hotkey_ newGroupName (AnswerMap formMapData) =
    (case hotkeyToIndex hotkey_ of
        Just index ->
            let
                existingMapping =
                    List.length formMapData.existingMapping
            in
            if index < existingMapping then
                formMapData

            else
                { otherMapping =
                    List.updateAt
                        (index - existingMapping)
                        (\a -> { a | groupName = newGroupName })
                        formMapData.otherMapping
                , existingMapping = formMapData.existingMapping
                }

        Nothing ->
            formMapData
    )
        |> AnswerMap


removeGroup : Hotkey -> AnswerMap -> AnswerMap
removeGroup hotkey_ (AnswerMap formMapData) =
    (case hotkeyToIndex hotkey_ of
        Just index ->
            let
                existingMapping =
                    List.length formMapData.existingMapping
            in
            if index < existingMapping then
                formMapData

            else
                { otherMapping = List.removeAt (index - existingMapping) formMapData.otherMapping
                , existingMapping = formMapData.existingMapping
                }

        Nothing ->
            formMapData
    )
        |> AnswerMap


toggleMapping : Hotkey -> OtherAnswer -> AnswerMap -> AnswerMap
toggleMapping hotkey_ otherAnswer_ (AnswerMap formMapData) =
    (case hotkeyToIndex hotkey_ of
        Just index ->
            let
                existingMapping =
                    List.length formMapData.existingMapping
            in
            if index < existingMapping then
                { otherMapping = formMapData.otherMapping
                , existingMapping = List.updateAt index (toggleSet otherAnswer_) formMapData.existingMapping
                }

            else
                { otherMapping =
                    List.updateAt
                        (index - existingMapping)
                        (\a -> { a | otherAnswers = toggleSet otherAnswer_ a.otherAnswers })
                        formMapData.otherMapping
                , existingMapping = formMapData.existingMapping
                }

        Nothing ->
            formMapData
    )
        |> AnswerMap


addGroup : String -> AnswerMap -> AnswerMap
addGroup groupName (AnswerMap formMapData) =
    { otherMapping = formMapData.otherMapping ++ [ { groupName = groupName, otherAnswers = Set.empty } ]
    , existingMapping = formMapData.existingMapping
    }
        |> AnswerMap


toggleSet : a -> Set a -> Set a
toggleSet a set =
    if Set.member a set then
        Set.remove a set

    else
        Set.insert a set
