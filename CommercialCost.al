// Table Extension for Item Table
tableextension 50100 "Item Extension" extends Item
{
    fields
    {
        field(50100; "Commercial Cost"; Decimal)
        {
            Caption = 'Commercial Cost';
            DataClassification = CustomerContent;
            Editable = false;
            DecimalPlaces = 2;
        }

        field(50101; "Commercial Cost Calc. Method"; Enum "Commercial Cost Calculation")
        {
            Caption = 'Commercial Cost Calculation Method';
            DataClassification = CustomerContent;

            trigger OnValidate()
            begin
                if "Commercial Cost Calc. Method" <> "Commercial Cost Calc. Method"::"Manually Specified" then
                    CalculateCommercialCost();
            end;
        }

        field(50102; "Discount Percentage"; Decimal)
        {
            Caption = 'Discount Percentage';
            DataClassification = CustomerContent;
            MinValue = 0;
            MaxValue = 100;
            DecimalPlaces = 0 : 2;

            trigger OnValidate()
            begin
                // Ensure this field is only editable with correct calculation method
                if CurrFieldNo = FieldNo("Discount Percentage") then begin
                    if "Commercial Cost Calc. Method" <> "Commercial Cost Calc. Method"::"Discount from List Price" then
                        Error(DiscountPercentageNotEditableErr);

                    // Validate Unit Price exists
                    if "Unit Price" = 0 then
                        Error(UnitPriceRequiredErr);
                end;

                // Recalculate Commercial Cost if using Discount from List Price
                if "Commercial Cost Calc. Method" = "Commercial Cost Calc. Method"::"Discount from List Price" then
                    CalculateCommercialCost();
            end;
        }
    }

    var
        DiscountPercentageNotEditableErr: Label 'Discount Percentage can only be edited when Calculation Method is set to Discount from List Price.';
        UnitPriceRequiredErr: Label 'Unit Price must be specified before setting a Discount Percentage.';

    trigger OnBeforeModify()
    begin
        if "Commercial Cost Calc. Method" <> "Commercial Cost Calc. Method"::"Manually Specified" then
            CalculateCommercialCost();
    end;

    local procedure CalculateCommercialCost()
    var
        PurchasePrice: Record "Purchase Price";
        Math: Codeunit Math;
        MaxCost: Decimal;
    begin
        case "Commercial Cost Calc. Method" of
            "Commercial Cost Calc. Method"::Blank:
                "Commercial Cost" := Math.Max("Unit Cost", "Last Direct Cost");

            "Commercial Cost Calc. Method"::"Maximum Cost":
                begin
                    MaxCost := Math.Max("Unit Cost", "Last Direct Cost");
                    PurchasePrice.SetRange("Item No.", "No.");
                    if PurchasePrice.FindSet() then
                        repeat
                            MaxCost := Math.Max(MaxCost, PurchasePrice."Direct Unit Cost");
                        until PurchasePrice.Next() = 0;
                    "Commercial Cost" := MaxCost;
                end;

            "Commercial Cost Calc. Method"::"Last Direct Cost":
                "Commercial Cost" := "Last Direct Cost";

            "Commercial Cost Calc. Method"::"Average Cost":
                "Commercial Cost" := "Unit Cost";

            "Commercial Cost Calc. Method"::"Discount from List Price":
                begin
                    if "Unit Price" <> 0 then
                        "Commercial Cost" := "Unit Price" * (1 - "Discount Percentage" / 100);
                    if "Unit Price" = 0 then
                        Error(UnitPriceRequiredErr)
                end;

            "Commercial Cost Calc. Method"::"Manually Specified":
                ; // Do nothing, allow manual editing
        end;
        Modify();
    end;
}

// Enum for Commercial Cost Calculation Methods
enum 50100 "Commercial Cost Calculation"
{
    Extensible = true;

    value(0; Blank)
    {
        Caption = ' ';
    }
    value(1; "Maximum Cost")
    {
        Caption = 'Maximum Cost';
    }
    value(2; "Last Direct Cost")
    {
        Caption = 'Last Direct Cost';
    }
    value(3; "Average Cost")
    {
        Caption = 'Average Cost';
    }
    value(4; "Discount from List Price")
    {
        Caption = 'Discount from List Price';
    }
    value(5; "Manually Specified")
    {
        Caption = 'Manually Specified';
    }
}

// Page Extension for Item Card
pageextension 50100 "Item Card Extension" extends "Item Card"
{
    layout
    {
        addlast("Costs & Posting")
        {
            field("Commercial Cost"; Rec."Commercial Cost")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the commercial cost of the item.';
                Editable = CommercialCostEditable;
                Visible = IsInventoryItem;
            }
            field("Commercial Cost Calc. Method"; Rec."Commercial Cost Calc. Method")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies how the commercial cost should be calculated.';
                Visible = IsInventoryItem;
                trigger OnValidate()
                begin
                    UpdateEditability();
                    CurrPage.Update();
                end;
            }
            field("Discount Percentage"; Rec."Discount Percentage")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the discount percentage to calculate Commercial Cost from Unit Price.';
                Enabled = DiscountPercentageEnabled;
                Caption = 'Discount Percentage';
                Visible = IsInventoryItem;

                trigger OnValidate()
                begin
                    if Rec."Unit Price" = 0 then
                        Error(UnitPriceRequiredErr);
                end;
            }
        }

        modify("Unit Price")
        {
            trigger OnAfterValidate()
            var
                Item: Record Item;
            begin
                Item.Get(Rec."No.");
                if (Item."Commercial Cost Calc. Method" = Item."Commercial Cost Calc. Method"::"Discount from List Price") then begin
                    if (Rec."Unit Price" = 0) then begin
                        Item.Validate("Discount Percentage", 0);
                        Item.Modify(true);
                    end;
                    UpdateEditability();
                    CurrPage.Update(true);
                end;
            end;
        }

        modify("Type")
        {
            trigger OnAfterValidate()
            begin
                IsInventoryItem := (Rec.Type = Rec.Type::Inventory);
            end;
        }
    }

    var
        IsInventoryItem: Boolean; //Only show fields in invetory items
        UnitPriceRequiredErr: Label 'Unit Price must be specified before setting a Discount Percentage.';
        CommercialCostEditable: Boolean;
        DiscountPercentageEnabled: Boolean;

    trigger OnAfterGetRecord()
    begin
        IsInventoryItem := (Rec.Type = Rec.Type::Inventory);
        UpdateEditability();
    end;

    trigger OnNewRecord(BelowxRec: Boolean)
    begin
        IsInventoryItem := (Rec.Type = Rec.Type::Inventory);
        UpdateEditability();
    end;

    trigger OnOpenPage()
    begin
        IsInventoryItem := (Rec.Type = Rec.Type::Inventory);
    end;

    procedure UpdateEditability()
    begin
        CommercialCostEditable := Rec."Commercial Cost Calc. Method" = Rec."Commercial Cost Calc. Method"::"Manually Specified";

        if Rec."Commercial Cost Calc. Method" = Rec."Commercial Cost Calc. Method"::"Discount from List Price" then begin
            DiscountPercentageEnabled := Rec."Unit Price" <> 0;
        end
        else begin
            DiscountPercentageEnabled := false;
        end;

        if Rec."Commercial Cost Calc. Method" <> Rec."Commercial Cost Calc. Method"::"Discount from List Price" then
            Rec."Discount Percentage" := 0;
    end;
}