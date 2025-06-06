------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--              D I A G N O S T I C S . S A R I F _ E M I T T E R           --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--          Copyright (C) 1992-2025, Free Software Foundation, Inc.         --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT; see file COPYING3.  If not, go to --
-- http://www.gnu.org/licenses for a complete copy of the license.          --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

with Errout;                    use Errout;
with Diagnostics.JSON_Utils;    use Diagnostics.JSON_Utils;
with Diagnostics.Utils;         use Diagnostics.Utils;
with Gnatvsn;                   use Gnatvsn;
with Lib;                       use Lib;
with Namet;                     use Namet;
with Osint;                     use Osint;
with Output;                    use Output;
with Sinput;                    use Sinput;
with System.OS_Lib;

package body Diagnostics.SARIF_Emitter is

   --  SARIF attribute names

   N_ARTIFACT_CHANGES      : constant String := "artifactChanges";
   N_ARTIFACT_LOCATION     : constant String := "artifactLocation";
   N_COMMAND_LINE          : constant String := "commandLine";
   N_DELETED_REGION        : constant String := "deletedRegion";
   N_DESCRIPTION           : constant String := "description";
   N_DRIVER                : constant String := "driver";
   N_END_COLUMN            : constant String := "endColumn";
   N_END_LINE              : constant String := "endLine";
   N_EXECUTION_SUCCESSFUL  : constant String := "executionSuccessful";
   N_FIXES                 : constant String := "fixes";
   N_ID                    : constant String := "id";
   N_INSERTED_CONTENT      : constant String := "insertedContent";
   N_INVOCATIONS           : constant String := "invocations";
   N_LOCATIONS             : constant String := "locations";
   N_LEVEL                 : constant String := "level";
   N_MESSAGE               : constant String := "message";
   N_NAME                  : constant String := "name";
   N_ORIGINAL_URI_BASE_IDS : constant String := "originalUriBaseIds";
   N_PHYSICAL_LOCATION     : constant String := "physicalLocation";
   N_REGION                : constant String := "region";
   N_RELATED_LOCATIONS     : constant String := "relatedLocations";
   N_REPLACEMENTS          : constant String := "replacements";
   N_RESULTS               : constant String := "results";
   N_RULES                 : constant String := "rules";
   N_RULE_ID               : constant String := "ruleId";
   N_RUNS                  : constant String := "runs";
   N_SCHEMA                : constant String := "$schema";
   N_START_COLUMN          : constant String := "startColumn";
   N_START_LINE            : constant String := "startLine";
   N_TEXT                  : constant String := "text";
   N_TOOL                  : constant String := "tool";
   N_URI                   : constant String := "uri";
   N_URI_BASE_ID           : constant String := "uriBaseId";
   N_VERSION               : constant String := "version";

   --  We are currently using SARIF 2.1.0

   SARIF_Version : constant String := "2.1.0";
   pragma Style_Checks ("M100");
   SARIF_Schema  : constant String :=
     "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json";
   pragma Style_Checks ("M79");

   URI_Base_Id_Name : constant String := "PWD";
   --  We use the pwd as the originalUriBaseIds when providing absolute paths
   --  in locations.

   Current_Dir : constant String := Get_Current_Dir;
   --  Cached value of the current directory that is used in the URI_Base_Id
   --  and it is also the path that all other Uri attributes will be created
   --  relative to.

   type Artifact_Change is record
      File_Index  : Source_File_Index;
      --  Index for the source file

      Replacements : Edit_List;
      --  Regions of texts to be edited
   end record;

   procedure Destroy (Elem : in out Artifact_Change) is null;
   pragma Inline (Destroy);

   function Equals (L, R : Artifact_Change) return Boolean is
     (L.File_Index = R.File_Index);

   package Artifact_Change_Lists is new Doubly_Linked_Lists
     (Element_Type    => Artifact_Change,
      "="             => Equals,
      Destroy_Element => Destroy,
      Check_Tampering => False);

   subtype Artifact_Change_List is Artifact_Change_Lists.Doubly_Linked_List;

   function Get_Artifact_Changes (Fix : Fix_Type) return Artifact_Change_List;
   --  Group edits of a Fix into Artifact_Changes that organize the edits by
   --  file name.

   function Get_Unique_Rules (Diags : Diagnostic_List) return Diagnostic_List;
   --  Get a list of diagnostics that have unique Diagnostic Id-s.

   procedure Print_Replacement (Replacement : Edit_Type);
   --  Print a replacement node
   --
   --  {
   --    deletedRegion: {<Region>},
   --    insertedContent: {<Message>}
   --  }

   procedure Print_Fix (Fix : Fix_Type);
   --  Print the fix node
   --
   --  {
   --    description: {<Message>},
   --    artifactChanges: [<ArtifactChange>]
   --  }

   procedure Print_Fixes (Diag : Diagnostic_Type);
   --  Print the fixes node
   --
   --  "fixes": [
   --    <Fix>,
   --    ...
   --  ]

   procedure Print_Invocations;
   --  Print an invocations node that consists of
   --  * a single invocation node that consists of:
   --    * commandLine
   --    * executionSuccessful
   --
   --  "invocations": [
   --    {
   --      "commandLine": <command line arguments provided to the GNAT FE>,
   --      "executionSuccessful": ["true"|"false"],
   --    }
   --  ]

   procedure Print_Artifact_Change (A : Artifact_Change);
   --  Print an ArtifactChange node
   --
   --  {
   --    artifactLocation: {<ArtifactLocation>},
   --    replacements: [<Replacements>]
   --  }

   procedure Print_Artifact_Location (Sfile : Source_File_Index);
   --  Print an artifactLocation node
   --
   --   "artifactLocation": {
   --     "uri": <File_Name>,
   --     "uriBaseId": "PWD"
   --   }

   procedure Print_Location (Loc : Labeled_Span_Type;
                             Msg : String_Ptr);
   --  Print a location node that consists of
   --  * an optional message node
   --  * a physicalLocation node
   --    * ArtifactLocation node that consists of the file name
   --    * Region node that consists of the start and end positions of the span
   --
   --  {
   --    "message": {
   --      "text": <Msg>
   --    },
   --    "physicalLocation": {
   --      "artifactLocation": {
   --        "uri": <File_Name (Loc)>
   --      },
   --      "region": {
   --        "startLine": <Line(Loc.Fst)>,
   --        "startColumn": <Col(Loc.Fst)>,
   --        "endLine": <Line(Loc.Lst)>,
   --        "endColumn": Col(Loc.Lst)>
   --      }
   --    }
   --  }

   procedure Print_Locations (Diag : Diagnostic_Type);
   --  Print a locations node that consists of multiple location nodes. However
   --  typically just one location for the primary span of the diagnostic.
   --
   --   "locations": [
   --      <Location (Primary_Span (Diag))>
   --   ],

   procedure Print_Message (Text : String; Name : String := N_MESSAGE);
   --  Print a SARIF message node.
   --
   --  There are many message type nodes in the SARIF report however they can
   --  have a different node <Name>.
   --
   --  <Name>: {
   --    "text": <text>
   --  },

   procedure Print_Original_Uri_Base_Ids;
   --  Print the originalUriBaseIds that holds the PWD value
   --
   --  "originalUriBaseIds": {
   --    "PWD": {
   --      "uri": "<current_working_directory>"
   --    }
   --  },

   procedure Print_Related_Locations (Diag : Diagnostic_Type);
   --  Print a relatedLocations node that consists of multiple location nodes.
   --  Related locations are the non-primary spans of the diagnostic and the
   --  primary locations of sub-diagnostics.
   --
   --   "relatedLocations": [
   --      <Location (Diag.Loc)>
   --   ],

   procedure Print_Region (Start_Line : Int;
                           Start_Col  : Int;
                           End_Line   : Int;
                           End_Col    : Int;
                           Name       : String := N_REGION);
   --  Print a region node.
   --
   --  More specifically a text region node that specifies the textual
   --  location of the region. Note that in SARIF there are also binary
   --  regions.
   --
   --   "<Name>": {
   --     "startLine": Start_Line,
   --     "startColumn": Start_Col,
   --     "endLine": End_Line,
   --     "endColumn": End_Col + 1
   --   }
   --
   --  Note that there are many types of nodes that can have a region type,
   --  but have a different node name.
   --
   --  The end column is defined differently in the SARIF report than it is
   --  for the spans within GNAT. Internally we consider the end column of a
   --  span to be the last character of the span.
   --
   --  However in SARIF the end column is defined as:
   --  "The column number of the character following the end of the region"
   --
   --  This method assumes that the End_Col passed to this procedure is using
   --  the GNAT span definition and we amend the endColumn value so that it
   --  matches the SARIF definition.

   procedure Print_Result (Diag : Diagnostic_Type);
   --   {
   --     "ruleId": <Diag.Id>,
   --     "level": <Diag.Kind>,
   --     "message": {
   --       "text": <Diag.Message>
   --     },
   --     "locations": [<Primary_Location>],
   --     "relatedLocations": [<Secondary_Locations>]
   --  },

   procedure Print_Results (Diags : Diagnostic_List);
   --  Print a results node that consists of multiple result nodes for each
   --  diagnostic instance.
   --
   --   "results": [
   --     <Result (Diag)>
   --   ]

   procedure Print_Rule (Diag : Diagnostic_Type);
   --  Print a rule node that consists of the following attributes:
   --  * ruleId
   --  * name
   --
   --  {
   --    "id": <Diag.Id>,
   --    "name": <Human_Id(Diag)>
   --  },

   procedure Print_Rules (Diags : Diagnostic_List);
   --  Print a rules node that consists of multiple rule nodes.
   --  Rules are considered to be a set of unique diagnostics with the unique
   --  id-s.
   --
   --   "rules": [
   --     <Rule (Diag)>
   --   ]

   procedure Print_Runs (Diags : Diagnostic_List);
   --  Print a runs node that can consist of multiple run nodes.
   --  However for our report it consists of a single run that consists of
   --  * a tool node
   --  * a results node
   --
   --   {
   --     "tool": { <Tool (Diags)> },
   --     "results": [<Results (Diags)>]
   --   }

   procedure Print_Tool (Diags : Diagnostic_List);
   --  Print a tool node that consists of
   --  * a driver node that consists of:
   --    * name
   --    * version
   --    * rules
   --
   --  "tool": {
   --    "driver": {
   --      "name": "GNAT",
   --      "version": <GNAT_Version>,
   --      "rules": [<Rules (Diags)>]
   --    }
   --  }

   --------------------------
   -- Get_Artifact_Changes --
   --------------------------

   function Get_Artifact_Changes (Fix : Fix_Type) return Artifact_Change_List
   is
      procedure Insert (Changes : Artifact_Change_List; E : Edit_Type);

      ------------
      -- Insert --
      ------------

      procedure Insert (Changes : Artifact_Change_List; E : Edit_Type)
      is
         A : Artifact_Change;

         It : Artifact_Change_Lists.Iterator :=
           Artifact_Change_Lists.Iterate (Changes);
      begin
         while Artifact_Change_Lists.Has_Next (It) loop
            Artifact_Change_Lists.Next (It, A);

            if A.File_Index = Get_Source_File_Index (E.Span.Ptr) then
               Edit_Lists.Append (A.Replacements, E);
               return;
            end if;
         end loop;

         declare
            Replacements : constant Edit_List := Edit_Lists.Create;
         begin
            Edit_Lists.Append (Replacements, E);
            Artifact_Change_Lists.Append
              (Changes,
               (File_Index   => Get_Source_File_Index (E.Span.Ptr),
                Replacements => Replacements));
         end;
      end Insert;

      Changes : constant Artifact_Change_List := Artifact_Change_Lists.Create;

      E : Edit_Type;

      It : Edit_Lists.Iterator := Edit_Lists.Iterate (Fix.Edits);
   begin
      while Edit_Lists.Has_Next (It) loop
         Edit_Lists.Next (It, E);

         Insert (Changes, E);
      end loop;

      return Changes;
   end Get_Artifact_Changes;

   ----------------------
   -- Get_Unique_Rules --
   ----------------------

   function Get_Unique_Rules (Diags : Diagnostic_List)
                              return Diagnostic_List
   is
      use Diagnostics.Diagnostics_Lists;

      procedure Insert (Rules : Diagnostic_List; D : Diagnostic_Type);

      ------------
      -- Insert --
      ------------

      procedure Insert (Rules : Diagnostic_List; D : Diagnostic_Type) is
         It : Iterator := Iterate (Rules);
         R  : Diagnostic_Type;
      begin
         while Has_Next (It) loop
            Next (It, R);

            if R.Id = D.Id then
               return;
            elsif R.Id > D.Id then
               Insert_Before (Rules, R, D);
               return;
            end if;
         end loop;

         Append (Rules, D);
      end Insert;

      D : Diagnostic_Type;
      Unique_Rules : constant Diagnostic_List := Create;

      It : Iterator := Iterate (Diags);
   begin
      if Present (Diags) then
         while Has_Next (It) loop
            Next (It, D);
            Insert (Unique_Rules, D);
         end loop;
      end if;

      return Unique_Rules;
   end Get_Unique_Rules;

   ---------------------------
   -- Print_Artifact_Change --
   ---------------------------

   procedure Print_Artifact_Change (A : Artifact_Change)
   is
      use Diagnostics.Edit_Lists;
      E : Edit_Type;
      E_It : Iterator;

      First : Boolean := True;
   begin
      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      --  Print artifactLocation

      Print_Artifact_Location (A.File_Index);

      Write_Char (',');
      NL_And_Indent;

      Write_Str ("""" & N_REPLACEMENTS & """" & ": " & "[");
      Begin_Block;
      NL_And_Indent;

      E_It := Iterate (A.Replacements);

      while Has_Next (E_It) loop
         Next (E_It, E);

         if First then
            First := False;
         else
            Write_Char (',');
         end if;

         NL_And_Indent;
         Print_Replacement (E);
      end loop;

      --  End replacements

      End_Block;
      NL_And_Indent;
      Write_Char (']');

      --  End artifactChange

      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Artifact_Change;

   -----------------------------
   -- Print_Artifact_Location --
   -----------------------------

   procedure Print_Artifact_Location (Sfile : Source_File_Index) is
      Full_Name : constant String := Get_Name_String (Full_Ref_Name (Sfile));
   begin
      Write_Str ("""" & N_ARTIFACT_LOCATION & """" & ": " & "{");
      Begin_Block;
      NL_And_Indent;

      if System.OS_Lib.Is_Absolute_Path (Full_Name) then
         declare
            Abs_Name : constant String :=
              System.OS_Lib.Normalize_Pathname
                (Name => Full_Name, Resolve_Links => False);
         begin
            --  We cannot create relative paths between different drives on
            --  Windows. If the path is on a different drive than the PWD print
            --  the absolute path in the URI and omit the baseUriId attribute.

            if Osint.On_Windows
              and then Abs_Name (Abs_Name'First) =
                Current_Dir (Current_Dir'First)
            then
               Write_String_Attribute
                 (N_URI, To_File_Uri (Abs_Name));
            else
               Write_String_Attribute
                 (N_URI,
                  To_File_Uri
                    (Relative_Path (Abs_Name, Current_Dir)));

               Write_Char (',');
               NL_And_Indent;

               Write_String_Attribute
                 (N_URI_BASE_ID, URI_Base_Id_Name);
            end if;
         end;
      else
         --  If the path was not absolute it was given relative to the
         --  uriBaseId.

         Write_String_Attribute (N_URI, To_File_Uri (Full_Name));

         Write_Char (',');
         NL_And_Indent;

         Write_String_Attribute (N_URI_BASE_ID, URI_Base_Id_Name);
      end if;

      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Artifact_Location;

   -----------------------
   -- Print_Replacement --
   -----------------------

   procedure Print_Replacement (Replacement : Edit_Type) is
      --  Span start positions
      Fst      : constant Source_Ptr := Replacement.Span.First;
      Line_Fst : constant Int        := Int (Get_Physical_Line_Number (Fst));
      Col_Fst  : constant Int        := Int (Get_Column_Number (Fst));

      --  Span end positions
      Lst      : constant Source_Ptr := Replacement.Span.Last;
      Line_Lst : constant Int        := Int (Get_Physical_Line_Number (Lst));
      Col_Lst  : constant Int        := Int (Get_Column_Number (Lst));
   begin
      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      --  Print deletedRegion

      Print_Region (Start_Line => Line_Fst,
                    Start_Col  => Col_Fst,
                    End_Line   => Line_Lst,
                    End_Col    => Col_Lst,
                    Name       => N_DELETED_REGION);

      if Replacement.Text /= null then
         Write_Char (',');
         NL_And_Indent;

         Print_Message (Replacement.Text.all, N_INSERTED_CONTENT);
      end if;

      --  End replacement

      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Replacement;

   ---------------
   -- Print_Fix --
   ---------------

   procedure Print_Fix (Fix : Fix_Type) is
      First : Boolean := True;
   begin
      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      --  Print the message if the location has one

      if Fix.Description /= null then
         Print_Message (Fix.Description.all, N_DESCRIPTION);

         Write_Char (',');
         NL_And_Indent;
      end if;

      declare
         use Artifact_Change_Lists;
         Changes : Artifact_Change_List := Get_Artifact_Changes (Fix);
         A       : Artifact_Change;
         A_It    : Iterator := Iterate (Changes);
      begin
         Write_Str ("""" & N_ARTIFACT_CHANGES & """" & ": " & "[");
         Begin_Block;

         while Has_Next (A_It) loop
            Next (A_It, A);

            if First then
               First := False;
            else
               Write_Char (',');
            end if;

            NL_And_Indent;

            Print_Artifact_Change (A);
         end loop;

         End_Block;
         NL_And_Indent;
         Write_Char (']');

         Destroy (Changes);
      end;

      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Fix;

   -----------------
   -- Print_Fixes --
   -----------------

   procedure Print_Fixes (Diag : Diagnostic_Type) is
      use Diagnostics.Fix_Lists;
      F  : Fix_Type;
      F_It : Iterator;

      First : Boolean := True;
   begin
      Write_Str ("""" & N_FIXES & """" & ": " & "[");
      Begin_Block;

      if Present (Diag.Fixes) then
         F_It := Iterate (Diag.Fixes);
         while Has_Next (F_It) loop
            Next (F_It, F);

            if First then
               First := False;
            else
               Write_Char (',');
            end if;

            NL_And_Indent;
            Print_Fix (F);
         end loop;
      end if;

      End_Block;
      NL_And_Indent;
      Write_Char (']');
   end Print_Fixes;

   -----------------------
   -- Print_Invocations --
   -----------------------

   procedure Print_Invocations is

      function Compose_Command_Line return String;
      --  Composes the original command line from the parsed main file name and
      --  relevant compilation switches

      function Compose_Command_Line return String is
         Buffer : Bounded_String;
      begin
         Find_Program_Name;
         Append (Buffer, Name_Buffer (1 .. Name_Len));
         Append (Buffer, ' ');
         Append (Buffer, Get_First_Main_File_Name);
         for I in 1 .. Compilation_Switches_Last loop
            declare
               Switch : constant String := Get_Compilation_Switch (I).all;
            begin
               if Buffer.Length + Switch'Length + 1 <= Buffer.Max_Length then
                  Append (Buffer, ' ' & Switch);
               end if;
            end;
         end loop;

         return +Buffer;
      end Compose_Command_Line;

   begin
      Write_Str ("""" & N_INVOCATIONS & """" & ": " & "[");
      Begin_Block;
      NL_And_Indent;

      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      --  Print commandLine

      Write_String_Attribute (N_COMMAND_LINE, Compose_Command_Line);
      Write_Char (',');
      NL_And_Indent;

      --  Print executionSuccessful

      Write_Boolean_Attribute (N_EXECUTION_SUCCESSFUL, not Compilation_Errors);

      End_Block;
      NL_And_Indent;
      Write_Char ('}');

      End_Block;
      NL_And_Indent;
      Write_Char (']');
   end Print_Invocations;

   ------------------
   -- Print_Region --
   ------------------

   procedure Print_Region (Start_Line : Int;
                           Start_Col  : Int;
                           End_Line   : Int;
                           End_Col    : Int;
                           Name       : String := N_REGION)
   is

   begin
      Write_Str ("""" & Name & """" & ": " & "{");
      Begin_Block;
      NL_And_Indent;

      Write_Int_Attribute (N_START_LINE, Start_Line);
      Write_Char (',');
      NL_And_Indent;

      Write_Int_Attribute (N_START_COLUMN, Start_Col);
      Write_Char (',');
      NL_And_Indent;

      Write_Int_Attribute (N_END_LINE, End_Line);
      Write_Char (',');
      NL_And_Indent;

      --  Convert the end of the span to the definition of the endColumn
      --  for a SARIF region.

      Write_Int_Attribute (N_END_COLUMN, End_Col + 1);

      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Region;

   --------------------
   -- Print_Location --
   --------------------

   procedure Print_Location (Loc : Labeled_Span_Type;
                             Msg : String_Ptr)
   is

      --  Span start positions
      Fst      : constant Source_Ptr := Loc.Span.First;
      Line_Fst : constant Int        := Int (Get_Physical_Line_Number (Fst));
      Col_Fst  : constant Int        := Int (Get_Column_Number (Fst));

      --  Span end positions
      Lst      : constant Source_Ptr := Loc.Span.Last;
      Line_Lst : constant Int        := Int (Get_Physical_Line_Number (Lst));
      Col_Lst  : constant Int        := Int (Get_Column_Number (Lst));

   begin
      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      --  Print the message if the location has one

      if Msg /= null then
         Print_Message (Msg.all);

         Write_Char (',');
         NL_And_Indent;
      end if;

      Write_Str ("""" & N_PHYSICAL_LOCATION & """" & ": " & "{");
      Begin_Block;
      NL_And_Indent;

      --  Print artifactLocation

      Print_Artifact_Location (Get_Source_File_Index (Loc.Span.Ptr));

      Write_Char (',');
      NL_And_Indent;

      --  Print region

      Print_Region (Start_Line => Line_Fst,
                    Start_Col  => Col_Fst,
                    End_Line   => Line_Lst,
                    End_Col    => Col_Lst);

      End_Block;
      NL_And_Indent;
      Write_Char ('}');

      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Location;

   ---------------------
   -- Print_Locations --
   ---------------------

   procedure Print_Locations (Diag : Diagnostic_Type) is
      use Diagnostics.Labeled_Span_Lists;
      Loc : Labeled_Span_Type;
      It : Iterator := Iterate (Diag.Locations);

      First : Boolean := True;
   begin
      Write_Str ("""" & N_LOCATIONS & """" & ": " & "[");
      Begin_Block;

      while Has_Next (It) loop
         Next (It, Loc);

         --  Only the primary span is considered as the main location other
         --  spans are considered related locations

         if Loc.Is_Primary then
            if First then
               First := False;
            else
               Write_Char (',');
            end if;

            NL_And_Indent;
            Print_Location (Loc, Loc.Label);
         end if;
      end loop;

      End_Block;
      NL_And_Indent;
      Write_Char (']');

   end Print_Locations;

   -------------------
   -- Print_Message --
   -------------------

   procedure Print_Message (Text : String; Name : String := N_MESSAGE) is

   begin
      Write_Str ("""" & Name & """" & ": " & "{");
      Begin_Block;
      NL_And_Indent;
      Write_String_Attribute (N_TEXT, Text);
      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Message;

   ---------------------------------
   -- Print_Original_Uri_Base_Ids --
   ---------------------------------

   procedure Print_Original_Uri_Base_Ids is
   begin
      Write_Str ("""" & N_ORIGINAL_URI_BASE_IDS & """" & ": " & "{");
      Begin_Block;
      NL_And_Indent;

      Write_Str ("""" & URI_Base_Id_Name & """" & ": " & "{");
      Begin_Block;
      NL_And_Indent;

      Write_String_Attribute (N_URI, To_File_Uri (Current_Dir));

      End_Block;
      NL_And_Indent;
      Write_Char ('}');

      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Original_Uri_Base_Ids;

   -----------------------------
   -- Print_Related_Locations --
   -----------------------------

   procedure Print_Related_Locations (Diag : Diagnostic_Type) is
      Loc : Labeled_Span_Type;
      Loc_It : Labeled_Span_Lists.Iterator :=
        Labeled_Span_Lists.Iterate (Diag.Locations);

      Sub : Sub_Diagnostic_Type;
      Sub_It : Sub_Diagnostic_Lists.Iterator;

      First : Boolean := True;
   begin
      Write_Str ("""" & N_RELATED_LOCATIONS & """" & ": " & "[");
      Begin_Block;

      --  Related locations are the non-primary spans of the diagnostic

      while Labeled_Span_Lists.Has_Next (Loc_It) loop
         Labeled_Span_Lists.Next (Loc_It, Loc);

         --  Non-primary spans are considered related locations

         if not Loc.Is_Primary then
            if First then
               First := False;
            else
               Write_Char (',');
            end if;

            NL_And_Indent;
            Print_Location (Loc, Loc.Label);
         end if;
      end loop;

      --  And the sub-diagnostic locations

      if Sub_Diagnostic_Lists.Present (Diag.Sub_Diagnostics) then
         Sub_It := Sub_Diagnostic_Lists.Iterate (Diag.Sub_Diagnostics);

         while Sub_Diagnostic_Lists.Has_Next (Sub_It) loop
            Sub_Diagnostic_Lists.Next (Sub_It, Sub);

            declare
               Found : Boolean := False;

               Prim_Loc : Labeled_Span_Type;
            begin
               if Labeled_Span_Lists.Present (Sub.Locations) then
                  Loc_It := Labeled_Span_Lists.Iterate (Sub.Locations);
                  while Labeled_Span_Lists.Has_Next (Loc_It) loop
                     Labeled_Span_Lists.Next (Loc_It, Loc);

                     --  For sub-diagnostic locations, only the primary span is
                     --  considered.

                     if not Found and then Loc.Is_Primary then
                        Found    := True;
                        Prim_Loc := Loc;
                     end if;
                  end loop;
               else

                  --  If there are no locations for the sub-diagnostic then use
                  --  the primary location of the main diagnostic.

                  Found    := True;
                  Prim_Loc := Primary_Location (Diag);
               end if;

               --  For mapping sub-diagnostics to related locations we have to
               --  make some compromises in details.
               --
               --  Firstly we only make one entry that is for the primary span
               --  of the sub-diagnostic.
               --
               --  Secondly this span can also have a label. However this
               --  pattern is not advised and by default we include the message
               --  of the sub-diagnostic as the message in location node since
               --  it should have more information.

               if Found then
                  if First then
                     First := False;
                  else
                     Write_Char (',');
                  end if;
                  NL_And_Indent;
                  Print_Location (Prim_Loc, Sub.Message);
               end if;
            end;
         end loop;
      end if;

      End_Block;
      NL_And_Indent;
      Write_Char (']');

   end Print_Related_Locations;

   ------------------
   -- Print_Result --
   ------------------

   procedure Print_Result (Diag : Diagnostic_Type) is

   begin
      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      --  Print ruleId

      Write_String_Attribute (N_RULE_ID, "[" & To_String (Diag.Id) & "]");

      Write_Char (',');
      NL_And_Indent;

      --  Print level

      Write_String_Attribute (N_LEVEL, Kind_To_String (Diag));

      Write_Char (',');
      NL_And_Indent;

      --  Print message

      Print_Message (Diag.Message.all);

      Write_Char (',');
      NL_And_Indent;

      --  Print locations

      Print_Locations (Diag);

      Write_Char (',');
      NL_And_Indent;

      --  Print related locations

      Print_Related_Locations (Diag);

      Write_Char (',');
      NL_And_Indent;

      --  Print fixes

      Print_Fixes (Diag);

      End_Block;
      NL_And_Indent;

      Write_Char ('}');
   end Print_Result;

   -------------------
   -- Print_Results --
   -------------------

   procedure Print_Results (Diags : Diagnostic_List) is
      use Diagnostics.Diagnostics_Lists;

      D : Diagnostic_Type;

      It : Iterator := Iterate (All_Diagnostics);

      First : Boolean := True;
   begin
      Write_Str ("""" & N_RESULTS & """" & ": " & "[");
      Begin_Block;

      if Present (Diags) then
         while Has_Next (It) loop
            Next (It, D);

            if First then
               First := False;
            else
               Write_Char (',');
            end if;

            NL_And_Indent;
            Print_Result (D);
         end loop;
      end if;

      End_Block;
      NL_And_Indent;
      Write_Char (']');
   end Print_Results;

   ----------------
   -- Print_Rule --
   ----------------

   procedure Print_Rule (Diag : Diagnostic_Type) is
      Human_Id : constant String_Ptr := Get_Human_Id (Diag);
   begin
      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      Write_String_Attribute (N_ID, "[" & To_String (Diag.Id) & "]");
      Write_Char (',');
      NL_And_Indent;

      if Human_Id = null then
         Write_String_Attribute (N_NAME, "Uncategorized_Diagnostic");
      else
         Write_String_Attribute (N_NAME, Human_Id.all);
      end if;

      End_Block;
      NL_And_Indent;
      Write_Char ('}');
   end Print_Rule;

   -----------------
   -- Print_Rules --
   -----------------

   procedure Print_Rules (Diags : Diagnostic_List) is
      use Diagnostics.Diagnostics_Lists;

      R : Diagnostic_Type;
      Rules : constant Diagnostic_List := Get_Unique_Rules (Diags);

      It : Iterator := Iterate (Rules);

      First : Boolean := True;
   begin
      Write_Str ("""" & N_RULES & """" & ": " & "[");
      Begin_Block;

      while Has_Next (It) loop
         Next (It, R);

         if First then
            First := False;
         else
            Write_Char (',');
         end if;

         NL_And_Indent;
         Print_Rule (R);
      end loop;

      End_Block;
      NL_And_Indent;
      Write_Char (']');

   end Print_Rules;

   ----------------
   -- Print_Tool --
   ----------------

   procedure Print_Tool (Diags : Diagnostic_List) is

   begin
      Write_Str ("""" & N_TOOL & """" & ": " & "{");
      Begin_Block;
      NL_And_Indent;

      --  --  Attributes of tool

      Write_Str ("""" & N_DRIVER & """" & ": " & "{");
      Begin_Block;
      NL_And_Indent;

      --  Attributes of tool.driver

      Write_String_Attribute (N_NAME, "GNAT");
      Write_Char (',');
      NL_And_Indent;

      Write_String_Attribute (N_VERSION, Gnat_Version_String);
      Write_Char (',');
      NL_And_Indent;

      Print_Rules (Diags);

      --  End of tool.driver

      End_Block;
      NL_And_Indent;

      Write_Char ('}');

      --  End of tool

      End_Block;
      NL_And_Indent;

      Write_Char ('}');
   end Print_Tool;

   ----------------
   -- Print_Runs --
   ----------------

   procedure Print_Runs (Diags : Diagnostic_List) is

   begin
      Write_Str ("""" & N_RUNS & """" & ": " & "[");
      Begin_Block;
      NL_And_Indent;

      --  Runs can consist of multiple "run"-s. However the GNAT SARIF report
      --  only has one.

      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      --  A run consists of a tool

      Print_Tool (Diags);

      Write_Char (',');
      NL_And_Indent;

      --  A run consists of an invocation
      Print_Invocations;

      Write_Char (',');
      NL_And_Indent;

      Print_Original_Uri_Base_Ids;
      Write_Char (',');
      NL_And_Indent;

      --  A run consists of results

      Print_Results (Diags);

      --  End of run

      End_Block;
      NL_And_Indent;

      Write_Char ('}');

      End_Block;
      NL_And_Indent;

      --  End of runs

      Write_Char (']');
   end Print_Runs;

   ------------------------
   -- Print_SARIF_Report --
   ------------------------

   procedure Print_SARIF_Report (Diags : Diagnostic_List) is
   begin
      Write_Char ('{');
      Begin_Block;
      NL_And_Indent;

      Write_String_Attribute (N_SCHEMA, SARIF_Schema);
      Write_Char (',');
      NL_And_Indent;

      Write_String_Attribute (N_VERSION, SARIF_Version);
      Write_Char (',');
      NL_And_Indent;

      Print_Runs (Diags);

      End_Block;
      NL_And_Indent;
      Write_Char ('}');

      Write_Eol;
   end Print_SARIF_Report;

end Diagnostics.SARIF_Emitter;
