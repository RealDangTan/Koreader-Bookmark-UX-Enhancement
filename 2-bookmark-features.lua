--[[--
User patch: bookmark feature pack for KOReader v2026.03+

Adds the bookmark-title behavior from the locally modified modules without
replacing whole KOReader modules. The patch wraps stock methods where possible
so future KOReader updates keep their own bug fixes and UI changes.

Features:
  - custom title per bookmark/highlight
  - optional title prompt when saving a highlight
  - book title stored on annotations
  - sort bookmark list by book name
  - optional chapter prefix in bookmark list rows
  - filter bookmark list by chapter
  - richer bookmark details header

Install as:
  <koreader>/patches/2-bookmark-features.lua
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local Event = require("ui/event")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template
local unpack_ = unpack or table.unpack

local function getDocTitle(reader)
    return reader.ui and reader.ui.doc_props and reader.ui.doc_props.display_title or nil
end

local function addBookmarkFields(reader, item, title)
    if type(item) ~= "table" then return end
    if title ~= nil then
        item.title = title
    end
    if item.book_title == nil then
        item.book_title = getDocTitle(reader)
    end
end

local function withPatchedAddItem(annotation, patch_item, fn)
    local orig_addItem = annotation.addItem
    annotation.addItem = function(annotation_self, item, ...)
        patch_item(item)
        return orig_addItem(annotation_self, item, ...)
    end

    local result = { pcall(fn) }
    annotation.addItem = orig_addItem
    if not result[1] then
        error(result[2])
    end
    return select(2, unpack_(result))
end

-- Keep title/book_title when old bookmark/highlight records are converted into
-- current annotation records.
do
    local ReaderAnnotation = require("apps/reader/modules/readerannotation")
    local orig_buildAnnotation = ReaderAnnotation.buildAnnotation

    function ReaderAnnotation:buildAnnotation(bm, highlights, init)
        local annotation = orig_buildAnnotation(self, bm, highlights, init)
        if annotation == nil then return annotation end
        annotation.title = bm.title
        annotation.book_title = bm.book_title
        if annotation.book_title == nil and self.ui.doc_props then
            annotation.book_title = self.ui.doc_props.display_title
        end
        return annotation
    end
end

do
    local ReaderBookmark = require("apps/reader/modules/readerbookmark")

    local orig_addToMainMenu = ReaderBookmark.addToMainMenu
    function ReaderBookmark:addToMainMenu(menu_items)
        orig_addToMainMenu(self, menu_items)

        local settings = menu_items.bookmarks_settings
        local sub = settings and settings.sub_item_table
        if type(sub) ~= "table" or sub._bookmark_patch_done then return end
        sub._bookmark_patch_done = true

        local show_chapter_item = {
            text = _("Show chapter in bookmark items"),
            checked_func = function()
                return G_reader_settings:isTrue("bookmarks_show_chapter_in_items")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("bookmarks_show_chapter_in_items")
            end,
        }
        local ask_title_item = {
            text = _("Ask for bookmark title on highlight"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("bookmarks_ask_for_title")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("bookmarks_ask_for_title")
            end,
            separator = true,
        }

        local sort_sub
        local insert_at
        for i, entry in ipairs(sub) do
            if type(entry) == "table" then
                if entry.sub_item_table and entry.text_func then
                    local ok, label = pcall(entry.text_func)
                    if ok and type(label) == "string" and label:find(_("Sort by"), 1, true) then
                        sort_sub = entry.sub_item_table
                        insert_at = insert_at or i
                    end
                elseif entry.text == _("Also show default highlight color") then
                    insert_at = i + 1
                elseif entry.text == _("Show separator between items") then
                    insert_at = insert_at or i + 1
                end
            end
        end

        table.insert(sub, insert_at or #sub + 1, show_chapter_item)
        table.insert(sub, (insert_at or #sub) + 1, ask_title_item)

        if type(sort_sub) == "table" then
            local has_book
            local reverse_at
            for i, entry in ipairs(sort_sub) do
                if type(entry) == "table" then
                    if entry.checked_func then
                        local ok, checked = pcall(entry.checked_func)
                        if ok and checked and G_reader_settings:readSetting("bookmarks_items_sorting") == "book" then
                            has_book = true
                        end
                    end
                    if entry.text == _("Reverse sorting") then
                        reverse_at = i
                    elseif entry.text == _("date") then
                        entry.separator = nil
                    end
                    if entry.text == _("book name") then
                        has_book = true
                    end
                end
            end
            if not has_book then
                table.insert(sort_sub, reverse_at or #sort_sub + 1, self:genSortByMenuItems("book", true))
            end
        end
    end

    local orig_genSortByMenuItems = ReaderBookmark.genSortByMenuItems
    function ReaderBookmark:genSortByMenuItems(value, separator)
        if value == "book" then
            return {
                text = _("book name"),
                checked_func = function()
                    return G_reader_settings:readSetting("bookmarks_items_sorting") == "book"
                end,
                radio = true,
                callback = function()
                    G_reader_settings:saveSetting("bookmarks_items_sorting", "book")
                end,
                separator = separator,
            }
        end
        if value == nil and G_reader_settings:readSetting("bookmarks_items_sorting") == "book" then
            return G_reader_settings:isTrue("bookmarks_items_reverse_sorting")
                and _("book name, reverse") or _("book name")
        end
        return orig_genSortByMenuItems(self, value, separator)
    end

    local orig_toggleBookmark = ReaderBookmark.toggleBookmark
    function ReaderBookmark:toggleBookmark(...)
        local args = { ... }
        return withPatchedAddItem(self.ui.annotation, function(item)
            addBookmarkFields(self, item)
        end, function()
            return orig_toggleBookmark(self, unpack_(args))
        end)
    end

    local orig_getBookmarkItemText = ReaderBookmark.getBookmarkItemText
    function ReaderBookmark:getBookmarkItemText(item)
        local text
        if item.title and item.title ~= "" then
            local item_type = item.type or self.getBookmarkType(item)
            text = self.display_prefix[item_type] .. item.title
            if self.sorting_mode == "date" then
                text = item.datetime .. "\u{2002}" .. text
            end
        else
            text = orig_getBookmarkItemText(self, item)
        end
        if G_reader_settings:isTrue("bookmarks_show_chapter_in_items") and item.chapter then
            text = "[" .. item.chapter .. "] " .. text
        end
        return text
    end

    local orig_getDialogHeader = ReaderBookmark._getDialogHeader
    function ReaderBookmark:_getDialogHeader(bookmark)
        local header = orig_getDialogHeader(self, bookmark)
        if bookmark.title and bookmark.title ~= "" then
            header = header .. "\n" .. T(_("Title: %1"), bookmark.title)
        end
        if bookmark.chapter then
            header = header .. "\n" .. T(_("Chapter: %1"), bookmark.chapter)
        end
        if bookmark.book_title then
            header = header .. "\n" .. T(_("Book: %1"), bookmark.book_title)
        end
        return header
    end

    local orig_getBookmarkItemIndex = ReaderBookmark.getBookmarkItemIndex
    function ReaderBookmark:getBookmarkItemIndex(item)
        if self.show_chapter_only then
            return self.ui.annotation:getItemIndex(item)
        end
        return orig_getBookmarkItemIndex(self, item)
    end

    local orig_updateBookmarkList = ReaderBookmark.updateBookmarkList
    function ReaderBookmark:updateBookmarkList(item_table, item_number)
        if not self.show_chapter_only then
            return orig_updateBookmarkList(self, item_table, item_number)
        end

        local bm_menu = self.bookmark_menu[1]
        local title
        if item_table then
            title = T(_("Bookmarks (%1)"), #item_table)
        end
        local subtitle
        if bm_menu.select_count then
            subtitle = T(_("Selected: %1"), bm_menu.select_count)
        else
            subtitle = _("Chapter:") .. " " .. self.show_chapter_only
        end
        bm_menu:switchItemTable(title, item_table, item_number, nil, subtitle)
    end

    function ReaderBookmark:editBookmarkTitle(item_or_index, caller_callback)
        local item, index
        if self.bookmark_menu then
            item = item_or_index
            index = self:getBookmarkItemIndex(item)
        else
            index = item_or_index
            item = self.ui.annotation.annotations[index]
        end

        local annotation = self.ui.annotation.annotations[index]
        local input_dialog
        input_dialog = InputDialog:new{
            title = _("Edit bookmark title"),
            description = "   " .. self:_getDialogHeader(item),
            input = annotation.title or "",
            input_hint = _("Leave empty to use highlighted text"),
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(input_dialog)
                        end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            local new_title = input_dialog:getInputText()
                            if new_title == "" then
                                new_title = nil
                            end
                            annotation.title = new_title
                            if item then
                                item.title = new_title
                                item.text = self:getBookmarkItemText(item)
                            end
                            self.ui:handleEvent(Event:new("AnnotationsModified", { annotation }))
                            UIManager:close(input_dialog)
                            if caller_callback then
                                caller_callback()
                            end
                        end,
                    },
                }
            },
        }
        UIManager:show(input_dialog)
        input_dialog:onShowKeyboard()
    end

    function ReaderBookmark:filterByChapter()
        local bm_menu = self.bookmark_menu[1]
        local item_table = bm_menu.item_table
        local chapters = {}
        local chapter_list = {}
        local no_chapter_label = _("No chapter")

        for _idx, item in ipairs(item_table) do
            local chapter = item.chapter
            if chapter == nil or chapter == "" then
                chapter = no_chapter_label
            end
            if not chapters[chapter] then
                chapters[chapter] = 0
                table.insert(chapter_list, chapter)
            end
            chapters[chapter] = chapters[chapter] + 1
        end

        table.sort(chapter_list, function(a, b)
            if a == no_chapter_label then return false end
            if b == no_chapter_label then return true end
            return a < b
        end)

        local buttons = {}
        for _idx, chapter in ipairs(chapter_list) do
            table.insert(buttons, {
                {
                    text = T("%1 (%2)", chapter, chapters[chapter]),
                    callback = function()
                        UIManager:close(self.chapter_dialog)
                        for i = #item_table, 1, -1 do
                            local item_chapter = item_table[i].chapter
                            if item_chapter == nil or item_chapter == "" then
                                item_chapter = no_chapter_label
                            end
                            if item_chapter ~= chapter then
                                table.remove(item_table, i)
                            end
                        end
                        self.show_chapter_only = chapter
                        self:updateBookmarkList(item_table)
                    end,
                },
            })
        end

        self.chapter_dialog = ButtonDialog:new{
            title = _("Filter by chapter"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(self.chapter_dialog)
    end

    function ReaderBookmark:_bookmarkPatchSortByBook()
        local bm_menu = self.bookmark_menu and self.bookmark_menu[1]
        if not (bm_menu and self.sorting_mode == "book" and type(bm_menu.item_table) == "table") then
            return
        end

        local item_table = bm_menu.item_table
        table.sort(item_table, function(a, b)
            local a_book = a.book_title or ""
            local b_book = b.book_title or ""
            if a_book == b_book then
                if self.is_reverse_sorting then
                    return a.datetime > b.datetime
                end
                return a.datetime < b.datetime
            end
            if self.is_reverse_sorting then
                return a_book > b_book
            end
            return a_book < b_book
        end)

        local curr_page = self:getBookmarkPageString(self:getCurrentPageNumber())
        local focus_idx = 1
        for i, item in ipairs(item_table) do
            if item.mandatory == curr_page then
                focus_idx = i
                break
            end
        end
        self:updateBookmarkList(item_table, focus_idx)
    end

    function ReaderBookmark:_bookmarkPatchInjectChapterFilter(buttons, bm_menu)
        if buttons._bookmark_patch_chapter_filter then return end
        buttons._bookmark_patch_chapter_filter = true

        local row = {
            {
                text = _("Filter by chapter"),
                enabled = #bm_menu.item_table > 0,
                callback = function()
                    if bm_menu._bookmark_patch_dialog then
                        UIManager:close(bm_menu._bookmark_patch_dialog)
                    end
                    self:filterByChapter()
                end,
            },
        }

        local insert_at = #buttons + 1
        for i, button_row in ipairs(buttons) do
            if type(button_row) == "table" then
                for _idx, button in ipairs(button_row) do
                    if type(button) == "table" and button.text == _("Filter by highlight color") then
                        insert_at = i + 1
                        break
                    end
                end
            end
            if insert_at == i + 1 then break end
        end
        table.insert(buttons, insert_at, row)
    end

    function ReaderBookmark:_bookmarkPatchHookBookmarkMenu()
        local bm_menu = self.bookmark_menu and self.bookmark_menu[1]
        if not bm_menu or bm_menu._bookmark_patch_hooked then return end
        bm_menu._bookmark_patch_hooked = true

        local bookmark = self
        local orig_tap = bm_menu.onLeftButtonTap
        function bm_menu:onLeftButtonTap(...)
            local old_new = ButtonDialog.new
            local active_menu = self
            ButtonDialog.new = function(class, options)
                local should_track_dialog
                if type(options) == "table" and options.title == _("Filter by bookmark type")
                        and type(options.buttons) == "table" then
                    bookmark:_bookmarkPatchInjectChapterFilter(options.buttons, active_menu)
                    should_track_dialog = true
                end
                local dialog = old_new(class, options)
                if should_track_dialog then
                    active_menu._bookmark_patch_dialog = dialog
                end
                return dialog
            end

            local result = { pcall(orig_tap, self, ...) }
            ButtonDialog.new = old_new
            if not result[1] then
                error(result[2])
            end
            return select(2, unpack_(result))
        end

        local orig_close = bm_menu.close_callback
        bm_menu.close_callback = function(...)
            bookmark.show_chapter_only = nil
            return orig_close(...)
        end
    end

    local orig_onShowBookmark = ReaderBookmark.onShowBookmark
    function ReaderBookmark:onShowBookmark(...)
        local result = { orig_onShowBookmark(self, ...) }
        self:_bookmarkPatchSortByBook()
        self:_bookmarkPatchHookBookmarkMenu()
        return unpack_(result)
    end

    local orig_showBookmarkDetails = ReaderBookmark.showBookmarkDetails
    function ReaderBookmark:showBookmarkDetails(item_or_index)
        local bm_menu = self.bookmark_menu and self.bookmark_menu[1]
        local item = bm_menu and item_or_index or self.ui.annotation.annotations[item_or_index]
        local bookmark = self
        local old_new = TextViewer.new
        TextViewer.new = function(class, options)
            local viewer
            if type(options) == "table" and options.text_type == "bookmark"
                    and type(options.buttons_table) == "table" then
                local title_button = {
                    {
                        text = item and item.title and _("Edit title") or _("Add title"),
                        enabled = not (bm_menu and bm_menu.select_count) and not bookmark.ui.highlight.select_mode,
                        callback = function()
                            if viewer then
                                UIManager:close(viewer)
                            end
                            bookmark:editBookmarkTitle(item_or_index, function()
                                if bm_menu then
                                    bookmark:updateBookmarkList(bm_menu.item_table, -1)
                                elseif bookmark.view.highlight.note_mark then
                                    UIManager:setDirty(bookmark.dialog, "ui")
                                end
                                bookmark:showBookmarkDetails(item_or_index)
                            end)
                        end,
                    },
                }

                local insert_at = #options.buttons_table
                for i, row in ipairs(options.buttons_table) do
                    if type(row) == "table" then
                        for _idx, button in ipairs(row) do
                            if type(button) == "table" and button.text == _("Remove bookmark") then
                                insert_at = i
                                break
                            end
                        end
                    end
                    if insert_at == i then break end
                end
                table.insert(options.buttons_table, insert_at, title_button)
            end
            viewer = old_new(class, options)
            return viewer
        end

        local result = { pcall(orig_showBookmarkDetails, self, item_or_index) }
        TextViewer.new = old_new
        if not result[1] then
            error(result[2])
        end
        return select(2, unpack_(result))
    end
end

do
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local orig_saveHighlight = ReaderHighlight.saveHighlight

    function ReaderHighlight:_bookmarkPatchSaveHighlightWithTitle(title, extend_to_sentence)
        return withPatchedAddItem(self.ui.annotation, function(item)
            addBookmarkFields(self, item, title)
        end, function()
            return orig_saveHighlight(self, extend_to_sentence)
        end)
    end

    function ReaderHighlight:showTitleInputDialog(extend_to_sentence)
        local input_dialog
        input_dialog = InputDialog:new{
            title = _("Enter bookmark title"),
            description = _("Leave empty to use highlighted text as title"),
            input_hint = _("Bookmark title (optional)"),
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(input_dialog)
                            self:clear()
                        end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            local title = input_dialog:getInputText()
                            UIManager:close(input_dialog)
                            self:_bookmarkPatchSaveHighlightWithTitle(
                                title ~= "" and title or nil,
                                extend_to_sentence)
                        end,
                    },
                },
            },
        }
        UIManager:show(input_dialog)
        input_dialog:onShowKeyboard()
    end

    function ReaderHighlight:saveHighlight(extend_to_sentence, skip_title_dialog)
        if self.hold_pos and not self.selected_text then
            self:highlightFromHoldPos()
        end
        if not skip_title_dialog and not self._bookmark_patch_skip_title_dialog
                and G_reader_settings:nilOrTrue("bookmarks_ask_for_title")
                and self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
            self:showTitleInputDialog(extend_to_sentence)
            return nil
        end
        return self:_bookmarkPatchSaveHighlightWithTitle(nil, extend_to_sentence)
    end

    function ReaderHighlight:addNote(text)
        local index = self:saveHighlight(true, true)
        if index then
            if text then
                self:clear()
            end
            self:editNote(index, true, text)
        end
    end

    local orig_startSelection = ReaderHighlight.startSelection
    function ReaderHighlight:startSelection(index)
        if index ~= nil then
            return orig_startSelection(self, index)
        end
        self._bookmark_patch_skip_title_dialog = true
        local result = { pcall(orig_startSelection, self, index) }
        self._bookmark_patch_skip_title_dialog = nil
        if not result[1] then
            error(result[2])
        end
        return select(2, unpack_(result))
    end

    if ReaderHighlight.importEmbeddedAnnotations then
        local orig_importEmbeddedAnnotations = ReaderHighlight.importEmbeddedAnnotations
        function ReaderHighlight:importEmbeddedAnnotations(...)
            self._bookmark_patch_skip_title_dialog = true
            local result = { pcall(orig_importEmbeddedAnnotations, self, ...) }
            self._bookmark_patch_skip_title_dialog = nil
            if not result[1] then
                error(result[2])
            end
            return select(2, unpack_(result))
        end
    end
end
